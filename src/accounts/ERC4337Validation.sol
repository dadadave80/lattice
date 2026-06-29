// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {IERC4337Validation} from "@lattice/interfaces/accounts/IERC4337Validation.sol";
import {IAccount, PackedUserOperation} from "@lattice/interfaces/external/IAccount.sol";

/// @title ERC4337Validation
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice ERC-4337 validation facet — makes the Diamond a smart account drivable by a configured EntryPoint.
///         `validateUserOp` gates on the EntryPoint, validates the user op signature against the `AccountSigner`
///         owner, and pays the EntryPoint its prefund.
/// @dev Stateless delegator — logic/storage live in {ERC4337ValidationLib}. The EntryPoint is configurable
///      (v0.7/v0.8/v0.9) rather than hardcoded.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source ERC-4337
contract ERC4337Validation is IAccount, IERC4337Validation {
    /// @inheritdoc IAccount
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        virtual
        returns (uint256 validationData)
    {
        return ERC4337ValidationLib.validateUserOp(userOp, userOpHash, missingAccountFunds);
    }

    /// @inheritdoc IERC4337Validation
    function entryPoint() external view virtual returns (address) {
        return ERC4337ValidationLib.entryPoint();
    }

    /// @inheritdoc IERC4337Validation
    function setEntryPoint(address entryPoint_) external virtual {
        ERC4337ValidationLib.setEntryPoint(entryPoint_);
    }
}
