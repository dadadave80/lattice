// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC6900TypesLib} from "@lattice/accounts/erc6900/libraries/ERC6900TypesLib.sol";
import {IERC6900ModuleManager} from "@lattice/interfaces/accounts/IERC6900ModuleManager.sol";
import {
    ExecutionDataView,
    ExecutionManifest,
    HookConfig,
    IERC6900Account,
    IERC6900Module,
    MAX_VALIDATION_ASSOC_HOOKS,
    ManifestExecutionFunction,
    ManifestExecutionHook,
    ModuleEntity,
    ValidationConfig,
    ValidationDataView,
    ValidationFlags
} from "@lattice/interfaces/external/IERC6900.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @notice Per-execution-selector install state. `module == address(0)` means the selector is not a
///         module-supplied execution function (it may still be a native facet selector).
struct ExecutionStorage {
    address module;
    bool skipRuntimeValidation;
    bool allowGlobalValidation;
    EnumerableSet.Bytes32Set executionHooks; // packed HookConfig (left-aligned bytes25 in a bytes32)
}

/// @notice Per-validation-function (`ModuleEntity`) install state.
struct ValidationStorage {
    /// @notice `isUserOpValidation` (0x01) | `isSignatureValidation` (0x02) | `isGlobal` (0x04). Sole source of
    ///         these flags — overwritten wholesale on (re)install.
    ValidationFlags validationFlags;
    /// @notice Pre-validation hooks, ORDERED, no dedupe, capped at {MAX_VALIDATION_ASSOC_HOOKS}.
    HookConfig[] validationHooks;
    /// @notice Execution hooks attached to this validation (deduped set).
    EnumerableSet.Bytes32Set executionHooks;
    /// @notice Selectors this validation function is permitted to validate.
    EnumerableSet.Bytes4Set selectors;
}

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC6900ModuleManager")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC6900_MODULE_MANAGER_STORAGE_SLOT =
    0x498a44bfdab4c9c01e0c660bf3b7240261bf444dc4c542e64dac94a83f534500;

/// @notice ERC-7201 namespaced storage for the ERC-6900 module registry.
/// @custom:storage-location erc7201:lattice.storage.ERC6900ModuleManager
struct ERC6900ModuleManagerStorage {
    /// @notice Execution functions per selector. APPEND-ONLY.
    mapping(bytes4 selector => ExecutionStorage) _executions;
    /// @notice Validation functions per `ModuleEntity`. APPEND-ONLY.
    mapping(ModuleEntity validationFunction => ValidationStorage) _validations;
    /// @notice ERC-165 interface-id refcount from installed-module manifests; mirrored into the Diamond's
    ///         ERC-165 map so the account advertises a module's interfaces while ≥1 module supplies it. APPEND-ONLY.
    mapping(bytes4 interfaceId => uint256 count) _interfaceRefCount;
}

/// @title ERC6900ModuleManagerLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic + ERC-7201 storage for the ERC-6900 module registry: the execution registry (selector →
///         module + exec hooks) and the validation registry (`ModuleEntity` → flags + selectors + validation
///         /exec hooks). Backs the `ERC6900ModuleManager` config facet and (via the read helpers) the
///         `IERC6900AccountView` loupe.
/// @dev Re-implemented FRESH from the ERC-6900 reference semantics (erc6900/reference-implementation @ 65892c2;
///      reference is GPL — not a dependency). Lattice-native deviations: ERC-7201 namespaced storage (not the
///      reference's plain-keccak slot); a Diamond facet-map shadow check in place of the reference's static
///      `KnownSelectorsLib.isNativeFunction` list (`diamondCut` is the sole selector authority); and the
///      account-or-admin `_authorizeConfig` model shared with the ERC-7579 flavor. Module callbacks are
///      data-gated (called only when their `bytes` arg is non-empty) and state is written BEFORE every callback;
///      `onInstall` failure reverts the whole install, `onUninstall` failure is swallowed into the event's
///      `onUninstallSucceeded` flag — matching the reference.
library ERC6900ModuleManagerLib {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.Bytes4Set;
    using ERC6900TypesLib for HookConfig;
    using ERC6900TypesLib for ModuleEntity;
    using ERC6900TypesLib for ValidationConfig;

    /// @dev ERC-6900 account identifier (`vendorname.accountname.semver`; names contain no period).
    string private constant _ACCOUNT_ID = "lattice.modular-account-6900.0.1.0";

    function erc6900ModuleManagerStorage() internal pure returns (ERC6900ModuleManagerStorage storage $) {
        assembly {
            $.slot := ERC6900_MODULE_MANAGER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function accountId() internal pure returns (string memory) {
        return _ACCOUNT_ID;
    }

    /// @notice The execution-function install state for `selector` (module, validation flags, exec hooks). A
    ///         native function — one the Diamond dispatches to a facet — reports the account itself as the module
    ///         (per `IERC6900AccountView`); `execute`/`executeBatch` additionally report `allowGlobalValidation`
    ///         (matching the executor's native validation-gated set). An unowned selector reports all zero.
    function getExecutionData(bytes4 selector) internal view returns (ExecutionDataView memory data) {
        ExecutionStorage storage e = erc6900ModuleManagerStorage()._executions[selector];
        if (e.module != address(0)) {
            data.module = e.module;
            data.skipRuntimeValidation = e.skipRuntimeValidation;
            data.allowGlobalValidation = e.allowGlobalValidation;
            data.executionHooks = _toHookConfigs(e.executionHooks);
        } else if (DiamondLib.selectorToFacet(DiamondLib.diamondStorage(), selector) != address(0)) {
            data.module = address(this);
            data.allowGlobalValidation =
                selector == IERC6900Account.execute.selector || selector == IERC6900Account.executeBatch.selector;
        }
    }

    /// @notice The validation-function install state for `validationFunction` (flags, hooks, selectors).
    function getValidationData(ModuleEntity validationFunction) internal view returns (ValidationDataView memory data) {
        ValidationStorage storage v = erc6900ModuleManagerStorage()._validations[validationFunction];
        data.validationFlags = v.validationFlags;
        data.validationHooks = v.validationHooks;
        data.executionHooks = _toHookConfigs(v.executionHooks);
        data.selectors = v.selectors.values();
    }

    /// @notice How many installed modules advertise `interfaceId` via their manifest (ERC-165 refcount).
    function interfaceRefCount(bytes4 interfaceId) internal view returns (uint256) {
        return erc6900ModuleManagerStorage()._interfaceRefCount[interfaceId];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              EXECUTION LIFECYCLE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Installs an execution module from its manifest. Order (matching the reference): execution
    ///         functions → execution hooks → interface ids → `onInstall`. State is written before the callback;
    ///         a reverting `onInstall` reverts the whole install ({ModuleInstallCallbackFailed}).
    function installExecution(address module, ExecutionManifest calldata manifest, bytes calldata installData)
        internal
    {
        _authorizeConfig();
        if (module == address(0)) revert IERC6900ModuleManager.NullModule();
        ERC6900ModuleManagerStorage storage $ = erc6900ModuleManagerStorage();

        uint256 n = manifest.executionFunctions.length;
        for (uint256 i; i < n; ++i) {
            ManifestExecutionFunction calldata ef = manifest.executionFunctions[i];
            bytes4 selector = ef.executionSelector;
            ExecutionStorage storage e = $._executions[selector];
            // Already claimed by a module (or appearing twice in this manifest).
            if (e.module != address(0)) revert IERC6900ModuleManager.ExecutionFunctionAlreadySet(selector);
            // Lattice-native shadow check (replaces the reference's static native-selector list): a module
            // execution function may not shadow a selector the Diamond already routes to a facet. Non-reverting
            // overload — the single-arg `selectorToFacet` reverts {FunctionDoesNotExist} on a miss.
            if (DiamondLib.selectorToFacet(DiamondLib.diamondStorage(), selector) != address(0)) {
                revert IERC6900ModuleManager.ExecutionFunctionShadowsFacet(selector);
            }
            e.module = module;
            e.skipRuntimeValidation = ef.skipRuntimeValidation;
            e.allowGlobalValidation = ef.allowGlobalValidation;
        }

        uint256 h = manifest.executionHooks.length;
        for (uint256 i; i < h; ++i) {
            ManifestExecutionHook calldata mh = manifest.executionHooks[i];
            HookConfig hookConfig =
                ERC6900TypesLib.packExecHook(ERC6900TypesLib.pack(module, mh.entityId), mh.isPreHook, mh.isPostHook);
            if (!$._executions[mh.executionSelector].executionHooks.add(_hookKey(hookConfig))) {
                revert IERC6900ModuleManager.ExecutionHookAlreadySet(hookConfig);
            }
        }

        uint256 idCount = manifest.interfaceIds.length;
        for (uint256 i; i < idCount; ++i) {
            _addInterface($, manifest.interfaceIds[i]);
        }

        _onInstall(module, installData);
        emit IERC6900Account.ExecutionInstalled(module, manifest);
    }

    /// @notice Uninstalls an execution module. Reverse-by-type of install (hooks → functions → interface ids),
    ///         then `onUninstall`. No ownership/installed checks (auth-gated); a reverting `onUninstall` is
    ///         SWALLOWED into the event's `onUninstallSucceeded` flag, never reverting the uninstall.
    function uninstallExecution(address module, ExecutionManifest calldata manifest, bytes calldata uninstallData)
        internal
    {
        _authorizeConfig();
        ERC6900ModuleManagerStorage storage $ = erc6900ModuleManagerStorage();

        uint256 h = manifest.executionHooks.length;
        for (uint256 i; i < h; ++i) {
            ManifestExecutionHook calldata mh = manifest.executionHooks[i];
            HookConfig hookConfig =
                ERC6900TypesLib.packExecHook(ERC6900TypesLib.pack(module, mh.entityId), mh.isPreHook, mh.isPostHook);
            // Removing an absent hook is a silent no-op (return value ignored).
            $._executions[mh.executionSelector].executionHooks.remove(_hookKey(hookConfig));
        }

        uint256 n = manifest.executionFunctions.length;
        for (uint256 i; i < n; ++i) {
            ExecutionStorage storage e = $._executions[manifest.executionFunctions[i].executionSelector];
            e.module = address(0);
            e.skipRuntimeValidation = false;
            e.allowGlobalValidation = false;
        }

        uint256 idCount = manifest.interfaceIds.length;
        for (uint256 i; i < idCount; ++i) {
            _removeInterface($, manifest.interfaceIds[i]);
        }

        bool onUninstallSucceeded = _onUninstall(module, uninstallData);
        emit IERC6900Account.ExecutionUninstalled(module, onUninstallSucceeded, manifest);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             VALIDATION LIFECYCLE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Installs (or updates) a validation function. Order (matching the reference): per hook
    ///         (store → `onInstall`) → selectors → flags → the validation module's own `onInstall`. Flags are
    ///         OVERWRITTEN wholesale (this is also the update path); selectors/hooks are only ever added.
    ///         Validation (pre-validation) hooks go to an ordered array (duplicates allowed, capped at
    ///         {MAX_VALIDATION_ASSOC_HOOKS}); execution hooks go to a deduped set.
    function installValidation(
        ValidationConfig validationConfig,
        bytes4[] calldata selectors,
        bytes calldata installData,
        bytes[] calldata hooks
    ) internal {
        _authorizeConfig();
        (ModuleEntity validationFunction, ValidationFlags flags) = validationConfig.unpack();
        ValidationStorage storage v = erc6900ModuleManagerStorage()._validations[validationFunction];

        uint256 hookCount = hooks.length;
        for (uint256 i; i < hookCount; ++i) {
            (HookConfig hookConfig, bytes calldata hookData) = _decodeHook(hooks[i]);
            if (hookConfig.isValidationHook()) {
                v.validationHooks.push(hookConfig);
                if (v.validationHooks.length > MAX_VALIDATION_ASSOC_HOOKS) {
                    revert IERC6900ModuleManager.PreValidationHookLimitExceeded();
                }
            } else if (!v.executionHooks.add(_hookKey(hookConfig))) {
                revert IERC6900ModuleManager.ExecutionHookAlreadySet(hookConfig);
            }
            _onInstall(hookConfig.module(), hookData);
        }

        uint256 selCount = selectors.length;
        for (uint256 i; i < selCount; ++i) {
            if (!v.selectors.add(selectors[i])) {
                revert IERC6900ModuleManager.ValidationAlreadySet(selectors[i], validationFunction);
            }
        }

        v.validationFlags = flags;

        _onInstall(validationConfig.module(), installData);
        emit IERC6900Account.ValidationInstalled(validationConfig.module(), validationConfig.entityId());
    }

    /// @notice Uninstalls a validation function. Order: clear flags → (if `hookUninstallData` non-empty) run hook
    ///         `onUninstall`s [validation hooks, then execution hooks] → wipe hooks/selectors → the validation
    ///         module's own `onUninstall`. Every `onUninstall` revert is swallowed into `onUninstallSucceeded`.
    ///         Passing empty `hookUninstallData` clears all state but skips every hook callback.
    function uninstallValidation(
        ModuleEntity validationFunction,
        bytes calldata uninstallData,
        bytes[] calldata hookUninstallData
    ) internal {
        _authorizeConfig();
        ValidationStorage storage v = erc6900ModuleManagerStorage()._validations[validationFunction];
        bool onUninstallSucceeded = true;

        // Clear flags first (the validation can no longer authorize anything before its teardown completes).
        v.validationFlags = ValidationFlags.wrap(0);

        // Hook teardown callbacks — read while still in storage. Validation hooks (array order) then execution
        // hooks (set order); `hookUninstallData` must line up 1:1 with that ordering.
        uint256 hookDataCount = hookUninstallData.length;
        if (hookDataCount > 0) {
            uint256 valLen = v.validationHooks.length;
            uint256 execLen = v.executionHooks.length();
            if (hookDataCount != valLen + execLen) revert IERC6900ModuleManager.ArrayLengthMismatch();
            uint256 idx;
            for (uint256 i; i < valLen; ++i) {
                onUninstallSucceeded =
                    _onUninstall(v.validationHooks[i].module(), hookUninstallData[idx++]) && onUninstallSucceeded;
            }
            for (uint256 i; i < execLen; ++i) {
                address hookModule = HookConfig.wrap(bytes25(v.executionHooks.at(i))).module();
                onUninstallSucceeded = _onUninstall(hookModule, hookUninstallData[idx++]) && onUninstallSucceeded;
            }
        }

        // Wipe state unconditionally.
        delete v.validationHooks;
        _drainBytes32(v.executionHooks);
        _drainBytes4(v.selectors);

        (address moduleAddr, uint32 entityId) = validationFunction.unpack();
        onUninstallSucceeded = _onUninstall(moduleAddr, uninstallData) && onUninstallSucceeded;
        emit IERC6900Account.ValidationUninstalled(moduleAddr, entityId, onUninstallSucceeded);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    function _toHookConfigs(EnumerableSet.Bytes32Set storage set) private view returns (HookConfig[] memory out) {
        bytes32[] memory raw = set.values();
        out = new HookConfig[](raw.length);
        for (uint256 i; i < raw.length; ++i) {
            out[i] = HookConfig.wrap(bytes25(raw[i]));
        }
    }

    /// @dev Set key for a HookConfig: the bytes25 left-aligned in a bytes32 (low 7 bytes zero).
    function _hookKey(HookConfig hookConfig) private pure returns (bytes32) {
        return bytes32(HookConfig.unwrap(hookConfig));
    }

    /// @dev Refcount a manifest interface id; advertise it via the Diamond's ERC-165 map on the first claim. The
    ///      refcount and the Diamond's native ERC-165 bits share one bool map, so a module may not refcount an id
    ///      the account already owns natively (bit set, refcount 0) — a later uninstall would clear that native
    ///      bit and desync the ERC-165 view. The ERC-165 invalid sentinel must always read false, so it too is
    ///      rejected. (Native ids are registered at construction, before any module install.)
    function _addInterface(ERC6900ModuleManagerStorage storage $, bytes4 interfaceId) private {
        if (
            interfaceId == 0xffffffff
                || ($._interfaceRefCount[interfaceId] == 0 && ERC165Lib.supportsInterface(interfaceId))
        ) {
            revert IERC6900ModuleManager.InvalidInterfaceId(interfaceId);
        }
        if (++$._interfaceRefCount[interfaceId] == 1) {
            ERC165Lib.erc165Storage().supportedInterfaces[interfaceId] = true;
        }
    }

    /// @dev Drop one manifest interface-id reference; retract from ERC-165 when the last module drops it. The
    ///      checked decrement panics on over-uninstall — matching the reference's refcount underflow.
    function _removeInterface(ERC6900ModuleManagerStorage storage $, bytes4 interfaceId) private {
        if (--$._interfaceRefCount[interfaceId] == 0) {
            ERC165Lib.erc165Storage().supportedInterfaces[interfaceId] = false;
        }
    }

    /// @dev Data-gated `onInstall`: skipped when `data` is empty; a revert is re-thrown as
    ///      {ModuleInstallCallbackFailed} (reverting the whole install).
    function _onInstall(address module, bytes calldata data) private {
        if (data.length == 0) return;
        try IERC6900Module(module).onInstall(data) {}
        catch (bytes memory reason) {
            revert IERC6900ModuleManager.ModuleInstallCallbackFailed(module, reason);
        }
    }

    /// @dev Data-gated `onUninstall`: skipped (treated as success) when `data` is empty; a revert is SWALLOWED
    ///      and reported as `false` so a malicious module cannot brick uninstallation.
    function _onUninstall(address module, bytes calldata data) private returns (bool) {
        if (data.length == 0) return true;
        try IERC6900Module(module).onUninstall(data) {
            return true;
        } catch {
            return false;
        }
    }

    /// @dev Splits an `installValidation` hook entry `abi.encodePacked(bytes25 HookConfig, bytes hookData)` at the
    ///      fixed 25-byte boundary. `h[25:]` bounds-checks the length (reverts if < 25); the calldataload reads
    ///      the leading 25 bytes (low 7 of the 32-byte word are masked off by the bytes25 cast).
    function _decodeHook(bytes calldata h) private pure returns (HookConfig hookConfig, bytes calldata hookData) {
        bytes32 raw;
        assembly ("memory-safe") {
            raw := calldataload(h.offset)
        }
        hookConfig = HookConfig.wrap(bytes25(raw));
        hookData = h[25:];
    }

    function _drainBytes32(EnumerableSet.Bytes32Set storage set) private {
        uint256 len = set.length();
        for (uint256 i; i < len; ++i) {
            set.remove(set.at(0));
        }
    }

    function _drainBytes4(EnumerableSet.Bytes4Set storage set) private {
        uint256 len = set.length();
        for (uint256 i; i < len; ++i) {
            set.remove(set.at(0));
        }
    }

    function _authorizeConfig() private view {
        if (msg.sender != address(this) && !AccessControlLib.hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert IERC6900ModuleManager.UnauthorizedModuleConfig(msg.sender);
        }
    }
}
