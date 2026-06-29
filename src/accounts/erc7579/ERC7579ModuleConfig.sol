// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC7579ModuleConfigLib} from "@lattice/accounts/erc7579/libraries/ERC7579ModuleConfigLib.sol";
import {IERC7579ModuleConfig} from "@lattice/interfaces/external/IERC7579.sol";

/// @title ERC7579ModuleConfig
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice ERC-7579 module-management facet: registers/uninstalls modules and runs batches submitted by an
///         installed executor module. v1 supports EXECUTOR modules (type 2). Together with the
///         `ERC7821Executor` facet (`execute` / `supportsExecutionMode`) the Diamond presents the ERC-7579
///         account surface.
/// @dev Stateless delegator — logic/storage live in {ERC7579ModuleConfigLib}. "Modules-as-facets": `diamondCut`
///      remains the selector authority; this registry tracks installed executor modules and gates
///      `executeFromExecutor`. Validator/hook/fallback consumption is a planned v2.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source ERC-7579
contract ERC7579ModuleConfig is IERC7579ModuleConfig {
    /// @inheritdoc IERC7579ModuleConfig
    function installModule(uint256 moduleTypeId, address module, bytes calldata initData) external virtual {
        ERC7579ModuleConfigLib.installModule(moduleTypeId, module, initData);
    }

    /// @inheritdoc IERC7579ModuleConfig
    function uninstallModule(uint256 moduleTypeId, address module, bytes calldata deInitData) external virtual {
        ERC7579ModuleConfigLib.uninstallModule(moduleTypeId, module, deInitData);
    }

    /// @inheritdoc IERC7579ModuleConfig
    function isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata additionalContext)
        external
        view
        virtual
        returns (bool)
    {
        return ERC7579ModuleConfigLib.isModuleInstalled(moduleTypeId, module, additionalContext);
    }

    /// @notice ERC-7579 account identifier, `"vendorname.accountname.semver"`.
    function accountId() external view virtual returns (string memory) {
        return ERC7579ModuleConfigLib.accountId();
    }

    /// @notice Whether `moduleTypeId` is supported (v1: EXECUTOR, type 2).
    function supportsModule(uint256 moduleTypeId) external view virtual returns (bool) {
        return ERC7579ModuleConfigLib.supportsModule(moduleTypeId);
    }

    /// @notice Runs a batch on behalf of an installed executor module (caller must be a type-2 module).
    function executeFromExecutor(bytes32 mode, bytes calldata executionCalldata)
        external
        payable
        virtual
        returns (bytes[] memory returnData)
    {
        return ERC7579ModuleConfigLib.executeFromExecutor(mode, executionCalldata);
    }
}
