// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC7821ExecutorLib} from "@lattice/accounts/erc7579/libraries/ERC7821ExecutorLib.sol";
import {IModuleConfig} from "@lattice/interfaces/accounts/IModuleConfig.sol";
import {
    IERC7579Hook,
    IERC7579Module,
    IERC7579ModuleConfig,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_FALLBACK,
    MODULE_TYPE_HOOK,
    MODULE_TYPE_VALIDATOR
} from "@lattice/interfaces/external/ercs/IERC7579.sol";
import {Call} from "@lattice/interfaces/external/ercs/IERC7821.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev Fallback-handler (type 3) call types: forward via CALL (with the original caller appended ERC-2771-style)
///      or DELEGATECALL (the handler runs in the account's own context).
bytes1 constant FALLBACK_CALLTYPE_CALL = 0x00;
bytes1 constant FALLBACK_CALLTYPE_DELEGATECALL = 0xff;

/// @notice A registered fallback handler + how the account forwards to it.
struct FallbackHandler {
    address handler;
    bytes1 callType;
}

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
    /// @notice FALLBACK (type 3) handlers per selector, consulted by `AccountDiamond` on a facet-map miss
    ///         (layered UNDER the facet map — `diamondCut` keeps selector authority). APPEND-ONLY.
    mapping(bytes4 selector => FallbackHandler) _fallbacks;
}

/// @title ERC7579ModuleConfigLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-7579 reference implementation (https://github.com/erc7579/erc7579-implementation)
/// @notice Logic + ERC-7201 storage for the ERC-7579 module registry, consuming all four module types:
///         EXECUTOR (2 — drives batches via `executeFromExecutor`), VALIDATOR (1 — authorizes user ops in
///         `ERC4337Validation`), HOOK (4 — the single global hook wrapping execution), and FALLBACK (3 —
///         per-selector handlers dispatched by `AccountDiamond` on a facet-map miss).
/// @dev `diamondCut` remains the SOLE selector authority ("modules-as-facets"); fallback handlers are layered
///      UNDER the facet map and may not shadow a facet selector. `execute` / `supportsExecutionMode` (completing
///      the ERC-7579 surface) live on the `ERC7821Executor` facet.
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
            || moduleTypeId == MODULE_TYPE_HOOK || moduleTypeId == MODULE_TYPE_FALLBACK;
    }

    /// @notice The installed global hook (type 4), or `address(0)` if none.
    function hook() internal view returns (address) {
        return erc7579ModuleConfigStorage()._hook;
    }

    /// @notice The fallback handler (type 3) for `selector`, or a zero-address handler if none. Read by
    ///         `AccountDiamond` on a facet-map miss.
    function fallbackHandlerFor(bytes4 selector) internal view returns (address handler, bytes1 callType) {
        FallbackHandler storage f = erc7579ModuleConfigStorage()._fallbacks[selector];
        return (f.handler, f.callType);
    }

    /// @dev For FALLBACK (type 3), `additionalContext` is `abi.encode(bytes4 selector)`; the module is "installed"
    ///      iff it is the registered handler for that selector. Other types key on `_installed[type][module]`.
    function isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata additionalContext)
        internal
        view
        returns (bool)
    {
        if (moduleTypeId == MODULE_TYPE_FALLBACK) {
            if (additionalContext.length < 32) return false;
            return erc7579ModuleConfigStorage()._fallbacks[abi.decode(additionalContext, (bytes4))].handler == module;
        }
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
        // FALLBACK (type 3): `initData = abi.encode(bytes4 selector, bytes1 callType, bytes handlerData)`. The
        // registry (`_fallbacks[selector]`), not the `_installed` flag, is the source of truth (one handler may
        // serve several selectors). `handlerData` — not the whole tuple — is what `onInstall` receives.
        if (moduleTypeId == MODULE_TYPE_FALLBACK) {
            (bytes4 selector, bytes1 callType, bytes memory handlerData) = abi.decode(initData, (bytes4, bytes1, bytes));
            if ($._fallbacks[selector].handler != address(0)) {
                revert IModuleConfig.ModuleAlreadyInstalled(moduleTypeId, $._fallbacks[selector].handler);
            }
            if (callType != FALLBACK_CALLTYPE_CALL && callType != FALLBACK_CALLTYPE_DELEGATECALL) {
                revert IModuleConfig.UnsupportedFallbackCallType(callType);
            }
            // Layer UNDER facets: a fallback may not shadow a selector the diamond already dispatches. Use the
            // non-reverting overload — the single-arg `selectorToFacet` reverts {FunctionDoesNotExist} on a miss.
            if (DiamondLib.selectorToFacet(DiamondLib.diamondStorage(), selector) != address(0)) {
                revert IModuleConfig.FallbackShadowsFacet(selector);
            }
            IERC7579Module(module).onInstall(handlerData); // CEI
            $._fallbacks[selector] = FallbackHandler(module, callType);
            emit IERC7579ModuleConfig.ModuleInstalled(moduleTypeId, module);
            return;
        }
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
        // FALLBACK (type 3): `deInitData = abi.encode(bytes4 selector, bytes handlerData)`; clear the per-selector
        // registry entry before `onUninstall` (fail-safe).
        if (moduleTypeId == MODULE_TYPE_FALLBACK) {
            (bytes4 selector, bytes memory handlerData) = abi.decode(deInitData, (bytes4, bytes));
            if ($._fallbacks[selector].handler != module) {
                revert IModuleConfig.ModuleNotInstalled(moduleTypeId, module);
            }
            delete $._fallbacks[selector];
            IERC7579Module(module).onUninstall(handlerData);
            emit IERC7579ModuleConfig.ModuleUninstalled(moduleTypeId, module);
            return;
        }
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
