// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC6900SignatureLib} from "@lattice/accounts/erc6900/libraries/ERC6900SignatureLib.sol";

/// @title ERC6900Signature
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-6900 reference implementation (https://github.com/erc6900/reference-implementation)
/// @notice ERC-6900 ERC-1271 signature-validation facet: `isValidSignature` routes to the validation module
///         named by the signature prefix, after binding the digest to this account's domain via ERC-7739. Part
///         of the ERC-6900 account blueprint (an alternative to the ERC-7579 `ERC1271Signature` facet); the two
///         are never cut into the same account.
/// @dev Stateless delegator — logic lives in {ERC6900SignatureLib}; it reads the registries owned by
///      {ERC6900ModuleManagerLib} and composes {ERC7739Lib}/{EIP712Lib}.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source ERC-6900
contract ERC6900Signature {
    /// @notice ERC-1271 contract-signature validation, ERC-7739-bound to this account's domain.
    function isValidSignature(bytes32 hash, bytes calldata signature) external view virtual returns (bytes4) {
        return ERC6900SignatureLib.isValidSignature(hash, signature);
    }
}
