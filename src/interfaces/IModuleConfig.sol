// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IModuleConfig
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Lattice-specific errors for the ERC-7579 `ERC7579ModuleConfig` facet. The standard module-lifecycle
///         functions + `ModuleInstalled`/`ModuleUninstalled` events live on the vendored `IERC7579ModuleConfig`;
///         `accountId` / `supportsModule` / `executeFromExecutor` are on the facet itself, completing the
///         ERC-7579 surface together with the `ERC7821Executor` facet's `execute` / `supportsExecutionMode`.
/// @dev v1 supports EXECUTOR modules (type 2) only.
interface IModuleConfig {
    /// @notice The module type is not supported (v1 supports only EXECUTOR, type 2).
    error UnsupportedModuleType(uint256 moduleTypeId);

    /// @notice The module does not report itself as the requested type (`isModuleType` returned false).
    error InvalidModuleForType(address module, uint256 moduleTypeId);

    /// @notice The module is not installed for the requested type.
    error ModuleNotInstalled(uint256 moduleTypeId, address module);

    /// @notice The module is already installed for the requested type.
    error ModuleAlreadyInstalled(uint256 moduleTypeId, address module);

    /// @notice The caller may not configure modules (must be the account itself or an admin).
    error UnauthorizedModuleConfig(address caller);

    /// @notice `executeFromExecutor` was called by an address that is not an installed executor module.
    error NotInstalledExecutor(address caller);
}
