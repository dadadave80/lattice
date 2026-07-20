// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {HookConfig, ModuleEntity} from "@lattice/interfaces/external/ercs/IERC6900.sol";

/// @title IERC6900ModuleManager
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-6900 reference implementation (https://github.com/erc6900/reference-implementation)
/// @notice Lattice-specific errors for the ERC-6900 module manager (`ERC6900ModuleManager` facet). The standard
///         install/uninstall functions + lifecycle events live on the vendored `IERC6900Account`; these errors
///         cover the install/uninstall failure modes of the FRESH Lattice implementation.
/// @dev Mirrors the ERC-6900 reference semantics with two Lattice-native substitutions: the reference's static
///      `KnownSelectorsLib.isNativeFunction` guard becomes a Diamond facet-map shadow check
///      ({ExecutionFunctionShadowsFacet}), and install/uninstall authorization is the account-or-admin
///      `_authorizeConfig` model ({UnauthorizedModuleConfig}) used by the ERC-7579 flavor.
interface IERC6900ModuleManager {
    /// @notice The caller may not configure modules (must be the account itself or an admin).
    error UnauthorizedModuleConfig(address caller);

    /// @notice `installExecution` was called with the zero address as the module.
    error NullModule();

    /// @notice An execution selector is already claimed by an installed module (or appears twice in one manifest).
    error ExecutionFunctionAlreadySet(bytes4 selector);

    /// @notice An execution selector would shadow a function the Diamond already dispatches to a facet — the
    ///         account's native surface. Replaces the reference's `NativeFunctionNotAllowed` (`diamondCut` is the
    ///         sole selector authority; module execution functions are layered under the facet map).
    error ExecutionFunctionShadowsFacet(bytes4 selector);

    /// @notice The same execution hook (module + entityId + pre/post flags) is already attached to the selector.
    error ExecutionHookAlreadySet(HookConfig hookConfig);

    /// @notice A module's `onInstall` reverted; the original revert data is forwarded in `revertReason`.
    error ModuleInstallCallbackFailed(address module, bytes revertReason);

    /// @notice `selector` is already in this validation function's allowed-selector set.
    error ValidationAlreadySet(bytes4 selector, ModuleEntity validationFunction);

    /// @notice A validation function would exceed `MAX_VALIDATION_ASSOC_HOOKS` (255) pre-validation hooks.
    error PreValidationHookLimitExceeded();

    /// @notice `hookUninstallData.length` did not equal the validation function's total installed-hook count.
    error ArrayLengthMismatch();

    /// @notice A manifest interface id may not be the ERC-165 invalid sentinel (`0xffffffff`) nor an id the
    ///         account already supports natively (its ERC-165 bit is set with no module reference) — refcounting
    ///         such an id would let a later uninstall clear a native bit and desync the account's ERC-165 view.
    error InvalidInterfaceId(bytes4 interfaceId);
}
