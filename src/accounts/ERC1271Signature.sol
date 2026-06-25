// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1271SignatureLib} from "@lattice/accounts/libraries/ERC1271SignatureLib.sol";
import {IERC1271} from "@lattice/interfaces/external/IERC1271.sol";

/// @title ERC1271Signature
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice ERC-1271 contract-signature facet. Lets the Diamond declare a signature valid (for permits,
///         Seaport orders, Permit2) when it is a valid signature from the configured `SignerECDSA` owner.
/// @dev Stateless delegator — logic lives in {ERC1271SignatureLib}. v1 verifies the owner signature over the
///      raw `hash`; ERC-7739 defensive rehashing (cross-account replay protection) is a planned hardening.
/// @custom:lattice-version 0.1.0
contract ERC1271Signature is IERC1271 {
    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes memory signature) external view virtual returns (bytes4) {
        return ERC1271SignatureLib.isValidSignature(hash, signature);
    }
}
