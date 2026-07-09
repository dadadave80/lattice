// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1271SignatureLib} from "@lattice/accounts/libraries/ERC1271SignatureLib.sol";
import {IERC1271} from "@lattice/interfaces/external/IERC1271.sol";

/// @title ERC1271Signature
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/draft-ERC7739Utils.sol)
/// @notice ERC-1271 contract-signature facet. Lets the Diamond declare a signature valid (for permits,
///         Seaport orders, Permit2) when it is a valid signature from the configured `AccountSigner` owner.
/// @dev Stateless delegator — logic lives in {ERC1271SignatureLib}. Implements ERC-7739 defensive rehashing:
///      accepts only nested `TypedDataSign` / `PersonalSign` envelopes bound to this account's EIP-712 domain
///      (a plain signature over the raw hash is rejected), defeating cross-account replay.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source ERC-7739
contract ERC1271Signature is IERC1271 {
    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature) external view virtual returns (bytes4) {
        return ERC1271SignatureLib.isValidSignature(hash, signature);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC1271Signature methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `isValidSignature(bytes32,bytes)` 0x1626ba7e
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"1626ba7e";
    }
}
