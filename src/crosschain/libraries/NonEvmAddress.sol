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
///      returned verbatim. Starknet `felt252` addressing (which needs a Stark-field range check the raw
///      `bytes32` down-convert does not perform) is layered on top via {parseV1ToFelt252}.
library NonEvmAddress {
    /// @notice The CASA/CAIP-350 ERC-7930 ChainType binary key for the `starknet` namespace.
    /// @dev Derivation: the ChainAgnostic namespaces registry (`ChainAgnostic/namespaces`,
    ///      `starknet/caip350.md`) assigns the `starknet` CAIP-104 namespace the ChainType binary key `0x0003`
    ///      (eip-155 = `0x0000`). The chain reference is the UTF-8 bytes of the Starknet chain-id string
    ///      (`SN_MAIN` = `0x534e5f4d41494e`); the address is the raw 32-byte big-endian felt252.
    bytes2 internal constant STARKNET_CHAIN_TYPE = 0x0003;

    /// @notice The Stark field prime `2**251 + 17 * 2**192 + 1`. Every Starknet felt252 (address, selector,
    ///         payload element) MUST be strictly below this value.
    uint256 internal constant FIELD_PRIME = 0x0800000000000011000000000000000000000000000000000000000000000001;

    /// @notice The parsed ERC-7930 address field exceeds the 32-byte `bytes32` capacity.
    error NonEvmAddressTooLong(uint256 length);

    /// @notice The parsed address field was empty (would right-align to bytes32(0)).
    error NonEvmAddressEmpty();

    /// @notice An eip-155 (EVM) address field was not the canonical 20 bytes — rejecting it prevents a malformed
    ///         short address from silently right-aligning into a WRONG bytes32 (irreversible for a token mint).
    error NonEvmAddressInvalidEvmWidth(uint256 length);

    /// @notice The parsed address field is not a valid Starknet felt252 (`value >= FIELD_PRIME`).
    error NonEvmAddressNotAFelt(uint256 value);

    /// @notice The parsed address field decodes to the zero felt (no valid Starknet contract lives at 0).
    error NonEvmAddressZeroFelt();

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

    /// @notice Parses a generic ERC-7930 (version 1) interoperable address whose address field is a Starknet
    ///         `felt252`, range-checking it against the Stark field prime.
    /// @param self The full ERC-7930 interoperable address bytes.
    /// @return chainType      The 2-byte ERC-7930 chain type (`0x0003` = starknet, see {STARKNET_CHAIN_TYPE}).
    /// @return chainReference The raw chain-reference bytes (UTF-8 chain-id string, e.g. `SN_MAIN`).
    /// @return felt           The address field as a validated felt252 (`0 < felt < FIELD_PRIME`).
    /// @dev Wraps {parseV1ToBytes32} (so all its canonical-width rules apply — including the eip-155 20-byte
    ///      rule, which stays untouched), then enforces `felt < FIELD_PRIME` (revert {NonEvmAddressNotAFelt})
    ///      and `felt != 0` (revert {NonEvmAddressZeroFelt}). The caller is responsible for checking the
    ///      chainType/chainReference against its expected Starknet chain.
    function parseV1ToFelt252(bytes memory self)
        internal
        pure
        returns (bytes2 chainType, bytes memory chainReference, uint256 felt)
    {
        bytes32 addr;
        (chainType, chainReference, addr) = parseV1ToBytes32(self);
        felt = uint256(addr);
        if (felt >= FIELD_PRIME) revert NonEvmAddressNotAFelt(felt);
        if (felt == 0) revert NonEvmAddressZeroFelt();
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
