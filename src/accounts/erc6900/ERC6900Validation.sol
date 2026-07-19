// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC6900ValidationLib} from "@lattice/accounts/erc6900/libraries/ERC6900ValidationLib.sol";
import {PackedUserOperation} from "@lattice/interfaces/external/ercs/IAccount.sol";

/// @title ERC6900Validation
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-6900 reference implementation (https://github.com/erc6900/reference-implementation)
/// @notice ERC-6900 ERC-4337 validation facet: the EntryPoint's `validateUserOp` entrypoint, routing to the
///         validation module named by the userOp signature prefix. Part of the ERC-6900 account blueprint
///         (an alternative to the ERC-7579 `ERC4337Validation` facet); the two are never cut into the same
///         account. Shares the EntryPoint configured via `ERC4337ValidationLib`.
/// @dev Stateless delegator — logic lives in {ERC6900ValidationLib}; it reads the registries owned by
///      {ERC6900ModuleManagerLib} and reuses the executor's validation-applicability gate.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source ERC-6900
contract ERC6900Validation {
    /// @notice ERC-4337 account validation. Only the configured EntryPoint may call.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        virtual
        returns (uint256 validationData)
    {
        return ERC6900ValidationLib.validateUserOp(userOp, userOpHash, missingAccountFunds);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC6900Validation methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `validateUserOp((address,uint256,bytes,bytes,bytes32,uint256,bytes32,bytes,bytes),bytes32,uint256)` 0x19822f7c
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"19822f7c";
    }
}
