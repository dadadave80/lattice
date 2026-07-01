// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @title NonEvmAddress
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Thin non-EVM addressing helper layered OVER the vendored OpenZeppelin ERC-7930
///         {InteroperableAddress} generic `formatV1`/`parseV1` (which handle ANY chainType / chainReference /
///         address bytes). Down-converts a parsed ERC-7930 address field (<= 32 bytes) into a right-aligned
///         `bytes32`, and formats a full 32-byte non-EVM address back out. This is the epic-sequenced-first
///         foundation for `bytes32` non-EVM remotes — e.g. the Circle CCTP `mintRecipient` down-convert, where
///         a 20-byte EVM recipient or a 32-byte non-EVM (Solana/Aptos/…) recipient must both land in a single
///         `bytes32` slot.
/// @dev Does NOT modify the vendored OZ library — it only composes its generic entrypoints. A 20-byte EVM
///      address ends in the low 20 bytes (`bytes32(uint256(uint160(addr)))`); a 32-byte non-EVM address is
///      returned verbatim. Starknet `felt252` (< the BN254/Stark prime) helpers — which need a range check the
///      raw `bytes32` down-convert does not perform — are DEFERRED to sub-task 9.
library NonEvmAddress {
    /// @notice The parsed ERC-7930 address field exceeds the 32-byte `bytes32` capacity.
    error NonEvmAddressTooLong(uint256 length);

    /// @notice The parsed address field was empty (would right-align to bytes32(0)).
    error NonEvmAddressEmpty();

    /// @notice An eip-155 (EVM) address field was not the canonical 20 bytes — rejecting it prevents a malformed
    ///         short address from silently right-aligning into a WRONG bytes32 (irreversible for a token mint).
    error NonEvmAddressInvalidEvmWidth(uint256 length);

    /// @notice Parses a generic ERC-7930 (version 1) interoperable address and right-aligns its address field
    ///         into a `bytes32`.
    /// @param self The full ERC-7930 interoperable address bytes.
    /// @return chainType      The 2-byte ERC-7930 chain type (`0x0000` = eip-155).
    /// @return chainReference The raw chain-reference bytes (e.g. the EVM chainId, big-endian).
    /// @return addr           The address field right-aligned into a `bytes32`: a 20-byte EVM address occupies
    ///                        the low 20 bytes; a 32-byte non-EVM address fills the whole word.
    /// @dev Reverts {NonEvmAddressTooLong} if the address field is longer than 32 bytes. The right-align shift
    ///      discards the (potentially dirty) trailing bytes of the `bytes memory` word, so no masking is needed.
    function parseV1ToBytes32(bytes memory self)
        internal
        pure
        returns (bytes2 chainType, bytes memory chainReference, bytes32 addr)
    {
        bytes memory raw;
        (chainType, chainReference, raw) = InteroperableAddress.parseV1(self);

        uint256 len = raw.length;
        if (len == 0) revert NonEvmAddressEmpty();
        if (len > 32) revert NonEvmAddressTooLong(len);
        // Enforce canonical widths so a malformed (short) field cannot silently right-align into the WRONG bytes32.
        // EVM (eip-155, chainType 0x0000) addresses MUST be exactly 20 bytes (mirrors BridgeFungibleLib's EVM check);
        // non-EVM addresses may be up to 32 (the caller/protocol defines the width; right-aligned per ERC-7930).
        if (chainType == bytes2(0x0000) && len != 20) revert NonEvmAddressInvalidEvmWidth(len);

        assembly ("memory-safe") {
            // `raw` data is left-aligned in its first word; shifting right by (32 - len) bytes right-aligns the
            // `len` significant bytes and drops the low (32 - len) trailing bytes (len == 32 => shift 0).
            addr := shr(mul(sub(32, len), 8), mload(add(raw, 0x20)))
        }
    }

    /// @notice Convenience over the generic {InteroperableAddress.formatV1} for a FULL 32-byte non-EVM address.
    /// @param chainType      The 2-byte ERC-7930 chain type.
    /// @param chainReference The chain-reference bytes.
    /// @param addr           The full 32-byte non-EVM address.
    /// @return The ERC-7930 (version 1) interoperable address bytes with a 32-byte address field.
    function formatV1(bytes2 chainType, bytes memory chainReference, bytes32 addr)
        internal
        pure
        returns (bytes memory)
    {
        return InteroperableAddress.formatV1(chainType, chainReference, abi.encodePacked(addr));
    }
}
