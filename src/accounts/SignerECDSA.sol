// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SignerECDSALib} from "@lattice/accounts/libraries/SignerECDSALib.sol";
import {ISignerECDSA} from "@lattice/interfaces/ISignerECDSA.sol";

/// @title SignerECDSA
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Single-owner ECDSA signer facet. The configured owner's signatures authorize ERC-4337
///         `validateUserOp` (see `ERC4337Validation`) and ERC-1271 `isValidSignature` (see `ERC1271Signature`).
/// @dev Stateless delegator — logic/storage live in {SignerECDSALib}. The owner may be an EOA or an ERC-1271
///      contract (validation routes through the repo's `SignatureChecker`).
/// @custom:lattice-version 0.1.0
contract SignerECDSA is ISignerECDSA {
    /// @inheritdoc ISignerECDSA
    function owner() external view virtual returns (address) {
        return SignerECDSALib.owner();
    }

    /// @inheritdoc ISignerECDSA
    function setOwner(address newOwner) external virtual {
        SignerECDSALib.setOwner(newOwner);
    }
}
