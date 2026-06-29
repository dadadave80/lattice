// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC6900ModuleManagerLib} from "@lattice/accounts/erc6900/libraries/ERC6900ModuleManagerLib.sol";
import {
    ExecutionDataView,
    IERC6900AccountView,
    ModuleEntity,
    ValidationDataView
} from "@lattice/interfaces/external/IERC6900.sol";

/// @title ERC6900AccountView
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice ERC-6900 account-introspection facet (the "loupe"): `getExecutionData` reports the install state of an
///         execution selector (module + validation flags + execution hooks; a native facet selector reports the
///         account itself as the implementer), and `getValidationData` reports a validation function's flags,
///         validation/execution hooks, and permitted selectors.
/// @dev Stateless delegator — logic/storage live in {ERC6900ModuleManagerLib}. Part of the ERC-6900 account
///      blueprint (an alternative to the ERC-7579 `DiamondLoupe`).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source ERC-6900
contract ERC6900AccountView is IERC6900AccountView {
    /// @inheritdoc IERC6900AccountView
    function getExecutionData(bytes4 selector) external view virtual returns (ExecutionDataView memory) {
        return ERC6900ModuleManagerLib.getExecutionData(selector);
    }

    /// @inheritdoc IERC6900AccountView
    function getValidationData(ModuleEntity validationFunction)
        external
        view
        virtual
        returns (ValidationDataView memory)
    {
        return ERC6900ModuleManagerLib.getValidationData(validationFunction);
    }
}
