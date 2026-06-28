// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC7821ExecutorLib} from "@lattice/accounts/libraries/ERC7821ExecutorLib.sol";
import {IModuleConfig} from "@lattice/interfaces/IModuleConfig.sol";
import {
    IERC7579Hook,
    IERC7579Module,
    IERC7579ModuleConfig,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_HOOK,
    MODULE_TYPE_VALIDATOR
} from "@lattice/interfaces/external/IERC7579.sol";
import {Call} from "@lattice/interfaces/external/IERC7821.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC7579ModuleConfig")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC7579_MODULE_CONFIG_STORAGE_SLOT =
    0xf5855f8dc57bbb54955d6871575c862d7a11401119f5a873c91e7ac60628d800;

/// @dev ERC-165 map slots for the three OZ ERC-7579 interfaces the Diamond supports (this facet + the
///      `ERC7821Executor` facet's `execute`/`supportsExecutionMode` complete `IERC7579Execution` and
///      `IERC7579AccountConfig`). `keccak256(abi.encode(bytes4(id), 0x9ca7f3e2…c1c4200))`.
bytes32 constant ERC165_MAP_IERC7579EXECUTION_SLOT = 0x1adc25256844eecf70d1111a7d897d059d6c39bccc33e2fe1bcdd0aa07e45227; // 0x3f3f9537
bytes32 constant ERC165_MAP_IERC7579ACCOUNTCONFIG_SLOT =
    0xca27659497801bbd07af0889ead6ea5a1a9b8739438e7af51464f7082b08ae43; // 0xbe1d6cf6
bytes32 constant ERC165_MAP_IERC7579MODULECONFIG_SLOT =
    0x1c2e0d7514777ddafe41add8aefc1cb6319fbc463de0c6eb0b00433efbdbdd41; // 0x232dbb4a

/// @notice ERC-7201 namespaced storage for the ERC-7579 module registry.
/// @custom:storage-location erc7201:lattice.storage.ERC7579ModuleConfig
struct ERC7579ModuleConfigStorage {
    /// @notice Installed modules per type: `_installed[moduleTypeId][module]`. APPEND-ONLY.
    mapping(uint256 moduleTypeId => mapping(address module => bool installed)) _installed;
    /// @notice The single global HOOK (type 4) wrapping the account's execution surface; 0 if none. APPEND-ONLY.
    address _hook;
}

/// @title ERC7579ModuleConfigLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic + ERC-7201 storage for the ERC-7579 module registry. Supports EXECUTOR modules (type 2) — an
///         installed executor may drive a batch via `executeFromExecutor` — and VALIDATOR modules (type 1),
///         selected per user-operation and consumed by `ERC4337Validation` (#58 follow-on).
/// @dev `diamondCut` remains the selector authority ("modules-as-facets"); this registry tracks installed
///      modules. `execute` / `supportsExecutionMode` (completing the ERC-7579 surface) live on the
///      `ERC7821Executor` facet. Hook (type 4) and fallback (type 3) consumption are subsequent follow-ons.
library ERC7579ModuleConfigLib {
    /// @dev ERC-7579 account identifier (`vendorname.accountname.semver`).
    string private constant _ACCOUNT_ID = "lattice.diamond-account.0.1.0";

    function erc7579ModuleConfigStorage() internal pure returns (ERC7579ModuleConfigStorage storage $) {
        assembly {
            $.slot := ERC7579_MODULE_CONFIG_STORAGE_SLOT
        }
    }

    /// @notice Registers the three ERC-7579 interface ids the Diamond supports.
    function __ERC7579ModuleConfig_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterfaces();
    }

    function registerInterfaces() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC7579EXECUTION_SLOT, true)
            sstore(ERC165_MAP_IERC7579ACCOUNTCONFIG_SLOT, true)
            sstore(ERC165_MAP_IERC7579MODULECONFIG_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function accountId() internal pure returns (string memory) {
        return _ACCOUNT_ID;
    }

    function supportsModule(uint256 moduleTypeId) internal pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR || moduleTypeId == MODULE_TYPE_VALIDATOR
            || moduleTypeId == MODULE_TYPE_HOOK;
    }

    /// @notice The installed global hook (type 4), or `address(0)` if none.
    function hook() internal view returns (address) {
        return erc7579ModuleConfigStorage()._hook;
    }

    function isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata) internal view returns (bool) {
        return erc7579ModuleConfigStorage()._installed[moduleTypeId][module];
    }

    /// @notice Whether `module` is installed as `moduleTypeId` — the context-free form for internal consumers
    ///         (e.g. the validation facet's per-op validator lookup).
    function isInstalled(uint256 moduleTypeId, address module) internal view returns (bool) {
        return erc7579ModuleConfigStorage()._installed[moduleTypeId][module];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 LIFECYCLE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Installs `module` as `moduleTypeId`. Caller must be the account itself or an admin; the module
    ///         must report the type via `isModuleType`. Calls `module.onInstall(initData)`.
    function installModule(uint256 moduleTypeId, address module, bytes calldata initData) internal {
        _authorizeConfig();
        if (!supportsModule(moduleTypeId)) revert IModuleConfig.UnsupportedModuleType(moduleTypeId);
        if (!IERC7579Module(module).isModuleType(moduleTypeId)) {
            revert IModuleConfig.InvalidModuleForType(module, moduleTypeId);
        }
        ERC7579ModuleConfigStorage storage $ = erc7579ModuleConfigStorage();
        if ($._installed[moduleTypeId][module]) revert IModuleConfig.ModuleAlreadyInstalled(moduleTypeId, module);
        // At most one global HOOK (type 4) wraps the account — uninstall the current one before replacing it.
        if (moduleTypeId == MODULE_TYPE_HOOK && $._hook != address(0)) {
            revert IModuleConfig.ModuleAlreadyInstalled(moduleTypeId, $._hook);
        }
        // CEI: run the module's init BEFORE recording it installed, so the flag is only ever set for a
        // fully-initialized module — and a (re-entrant) executor cannot drive `executeFromExecutor` mid-`onInstall`.
        IERC7579Module(module).onInstall(initData);
        $._installed[moduleTypeId][module] = true;
        if (moduleTypeId == MODULE_TYPE_HOOK) $._hook = module;
        emit IERC7579ModuleConfig.ModuleInstalled(moduleTypeId, module);
    }

    /// @notice Uninstalls `module`. Caller must be the account itself or an admin. Calls `onUninstall`.
    function uninstallModule(uint256 moduleTypeId, address module, bytes calldata deInitData) internal {
        _authorizeConfig();
        ERC7579ModuleConfigStorage storage $ = erc7579ModuleConfigStorage();
        if (!$._installed[moduleTypeId][module]) revert IModuleConfig.ModuleNotInstalled(moduleTypeId, module);
        $._installed[moduleTypeId][module] = false;
        if (moduleTypeId == MODULE_TYPE_HOOK) $._hook = address(0); // clear before onUninstall (fail-safe)
        IERC7579Module(module).onUninstall(deInitData);
        emit IERC7579ModuleConfig.ModuleUninstalled(moduleTypeId, module);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 EXECUTION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Runs a batch on behalf of `msg.sender`, which must be an installed executor module (type 2).
    ///         Wrapped by the global hook (if any), like the owner/session-key `execute` path.
    function executeFromExecutor(bytes32 mode, bytes calldata executionCalldata)
        internal
        returns (bytes[] memory results)
    {
        if (!erc7579ModuleConfigStorage()._installed[MODULE_TYPE_EXECUTOR][msg.sender]) {
            revert IModuleConfig.NotInstalledExecutor(msg.sender);
        }
        (Call[] memory calls,) = ERC7821ExecutorLib.decodeBatch(mode, executionCalldata);
        (address h, bytes memory hookData) = preExecutionHook(msg.data);
        results = ERC7821ExecutorLib.runCalls(calls);
        postExecutionHook(h, hookData);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   HOOKS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Runs the global hook's `preCheck` (if installed) before an execution, returning the hook and its
    ///         opaque context for the matching {postExecutionHook}. A reverting hook blocks the execution.
    function preExecutionHook(bytes calldata msgData) internal returns (address h, bytes memory hookData) {
        h = erc7579ModuleConfigStorage()._hook;
        if (h != address(0)) hookData = IERC7579Hook(h).preCheck(msg.sender, msg.value, msgData);
    }

    /// @notice Runs the global hook's `postCheck` (if `h` is non-zero) after an execution.
    function postExecutionHook(address h, bytes memory hookData) internal {
        if (h != address(0)) IERC7579Hook(h).postCheck(hookData);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    function _authorizeConfig() private view {
        if (msg.sender != address(this) && !AccessControlLib.hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert IModuleConfig.UnauthorizedModuleConfig(msg.sender);
        }
    }
}
