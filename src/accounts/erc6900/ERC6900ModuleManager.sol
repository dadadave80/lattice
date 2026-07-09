// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC6900ModuleManagerLib} from "@lattice/accounts/erc6900/libraries/ERC6900ModuleManagerLib.sol";
import {ExecutionManifest, ModuleEntity, ValidationConfig} from "@lattice/interfaces/external/IERC6900.sol";

/// @title ERC6900ModuleManager
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-6900 reference implementation (https://github.com/erc6900/reference-implementation)
/// @notice ERC-6900 module-configuration facet: installs/uninstalls execution modules (selector → module +
///         execution hooks) and validation modules (`ModuleEntity` → flags + selectors + validation/exec hooks).
///         The `execute` / `executeBatch` / `executeWithRuntimeValidation` dispatch surface (the rest of
///         `IERC6900Account`) lands in the executor facet; this facet is the install/uninstall half.
/// @dev Stateless delegator — logic/storage live in {ERC6900ModuleManagerLib}. Part of the ERC-6900 account
///      blueprint, an alternative flavor to the ERC-7579 stack (`ERC7579ModuleConfig`).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source ERC-6900
contract ERC6900ModuleManager {
    /// @notice Installs an execution module from its manifest (execution functions, execution hooks, interface ids).
    function installExecution(address module, ExecutionManifest calldata manifest, bytes calldata installData)
        external
        virtual
    {
        ERC6900ModuleManagerLib.installExecution(module, manifest, installData);
    }

    /// @notice Uninstalls an execution module (reverses its manifest).
    function uninstallExecution(address module, ExecutionManifest calldata manifest, bytes calldata uninstallData)
        external
        virtual
    {
        ERC6900ModuleManagerLib.uninstallExecution(module, manifest, uninstallData);
    }

    /// @notice Installs (or updates) a validation function with its allowed selectors and associated hooks.
    function installValidation(
        ValidationConfig validationConfig,
        bytes4[] calldata selectors,
        bytes calldata installData,
        bytes[] calldata hooks
    ) external virtual {
        ERC6900ModuleManagerLib.installValidation(validationConfig, selectors, installData, hooks);
    }

    /// @notice Uninstalls a validation function and tears down its selectors and hooks.
    function uninstallValidation(
        ModuleEntity validationFunction,
        bytes calldata uninstallData,
        bytes[] calldata hookUninstallData
    ) external virtual {
        ERC6900ModuleManagerLib.uninstallValidation(validationFunction, uninstallData, hookUninstallData);
    }

    /// @notice ERC-6900 account identifier, `"vendorname.accountname.semver"`.
    function accountId() external view virtual returns (string memory) {
        return ERC6900ModuleManagerLib.accountId();
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC6900ModuleManager methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `accountId()` 0x9cfd7cff
    ///      `installExecution(address,((bytes4,bool,bool)[],(bytes4,uint32,bool,bool)[],bytes4[]),bytes)` 0x001a63e9
    ///      `installValidation(bytes25,bytes4[],bytes,bytes[])` 0x1bbf564c
    ///      `uninstallExecution(address,((bytes4,bool,bool)[],(bytes4,uint32,bool,bool)[],bytes4[]),bytes)` 0x93b1dc61
    ///      `uninstallValidation(bytes24,bytes,bytes[])` 0xb6b1ccfe
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"9cfd7cff001a63e91bbf564c93b1dc61b6b1ccfe";
    }
}
