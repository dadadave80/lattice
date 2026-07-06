// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {NonEvmAddress} from "@lattice/crosschain/libraries/NonEvmAddress.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Test} from "forge-std/Test.sol";

/// @notice External harness so library reverts surface through an external call frame (for `vm.expectRevert`)
///         and so the internal library functions are exercised exactly as a consumer would call them.
contract NonEvmAddressHarness {
    function parseV1ToBytes32(bytes memory self)
        external
        pure
        returns (bytes2 chainType, bytes memory chainReference, bytes32 addr)
    {
        return NonEvmAddress.parseV1ToBytes32(self);
    }

    function formatV1(bytes2 chainType, bytes memory chainReference, bytes32 addr)
        external
        pure
        returns (bytes memory)
    {
        return NonEvmAddress.formatV1(chainType, chainReference, addr);
    }

    function parseV1ToFelt252(bytes memory self)
        external
        pure
        returns (bytes2 chainType, bytes memory chainReference, uint256 felt)
    {
        return NonEvmAddress.parseV1ToFelt252(self);
    }
}

/// @title NonEvmAddressTest
/// @notice Plain library unit test (NO diamond): proves the ERC-7930 `bytes32` down-convert right-aligns a
///         20-byte EVM address into the low 20 bytes, returns a 32-byte non-EVM address verbatim, reverts on a
///         > 32-byte address field, and that {NonEvmAddress.formatV1} round-trips a full 32-byte address.
contract NonEvmAddressTest is Test {
    NonEvmAddressHarness harness;

    bytes2 constant CHAIN_TYPE_EVM = 0x0000; // eip-155
    bytes2 constant CHAIN_TYPE_SOLANA = 0x0002; // arbitrary non-EVM chainType for the 32-byte case

    function setUp() public {
        harness = new NonEvmAddressHarness();
    }

    /// @notice A 20-byte EVM recipient right-aligns into the low 20 bytes = bytes32(uint256(uint160(addr))).
    function test_ParseEvm20ByteRightAligned() public view {
        address evm = address(0xc0FfeE00000000000000000000000000DeaDBEeF);
        bytes memory encoded = InteroperableAddress.formatEvmV1(8453, evm); // Base chainId

        (bytes2 chainType, bytes memory chainRef, bytes32 addr) = harness.parseV1ToBytes32(encoded);

        assertEq(chainType, CHAIN_TYPE_EVM, "eip-155 chainType");
        assertEq(addr, bytes32(uint256(uint160(evm))), "20-byte addr in low 20 bytes");
        // High 12 bytes must be zero.
        assertEq(uint256(addr) >> 160, 0, "high 12 bytes zeroed");
        // chainReference is the big-endian chainId (0x2105 == 8453).
        assertEq(uint256(bytes32(_padRight(chainRef)) >> (256 - 8 * chainRef.length)), 8453, "chainRef == chainId");
    }

    /// @notice A 32-byte non-EVM recipient (e.g. a Solana pubkey) is returned verbatim in the full word.
    function test_Parse32ByteNonEvmVerbatim() public view {
        bytes32 solanaKey = keccak256("some-solana-pubkey");
        bytes memory encoded = NonEvmAddress.formatV1(CHAIN_TYPE_SOLANA, hex"abcdef", solanaKey);

        (bytes2 chainType, bytes memory chainRef, bytes32 addr) = harness.parseV1ToBytes32(encoded);

        assertEq(chainType, CHAIN_TYPE_SOLANA, "non-EVM chainType preserved");
        assertEq(chainRef, hex"abcdef", "chainReference preserved");
        assertEq(addr, solanaKey, "32-byte addr returned verbatim");
    }

    /// @notice formatV1 -> parseV1ToBytes32 round-trips a full 32-byte address for any chainType/reference.
    function test_FormatV1RoundTrips() public view {
        bytes32 key = bytes32(uint256(0x1234567890abcdef));
        bytes memory encoded = harness.formatV1(CHAIN_TYPE_SOLANA, hex"01", key);
        (bytes2 chainType, bytes memory chainRef, bytes32 addr) = harness.parseV1ToBytes32(encoded);
        assertEq(chainType, CHAIN_TYPE_SOLANA);
        assertEq(chainRef, hex"01");
        assertEq(addr, key);
    }

    /// @notice An address field longer than 32 bytes cannot fit a bytes32 and must revert.
    function test_ParseRevertsOnAddressTooLong() public {
        // Build a valid ERC-7930 v1 address with a 33-byte address field via the generic OZ formatV1.
        bytes memory tooLong = InteroperableAddress.formatV1(CHAIN_TYPE_SOLANA, hex"01", new bytes(33));
        vm.expectRevert(abi.encodeWithSelector(NonEvmAddress.NonEvmAddressTooLong.selector, uint256(33)));
        harness.parseV1ToBytes32(tooLong);
    }

    /// @notice A boundary 32-byte address field is accepted (not off-by-one rejected).
    function test_ParseAccepts32ByteBoundary() public view {
        bytes memory encoded = InteroperableAddress.formatV1(CHAIN_TYPE_SOLANA, hex"01", new bytes(32));
        (,, bytes32 addr) = harness.parseV1ToBytes32(encoded);
        assertEq(addr, bytes32(0));
    }

    /// @notice Hardening (adversarial finding): a non-canonical (short) eip-155 address is rejected so a malformed
    ///         recipient cannot silently right-align into a WRONG bytes32 and irreversibly mint to the wrong address.
    function test_ParseRevertsOnMalformedEvmWidth() public {
        bytes memory malformed = InteroperableAddress.formatV1(CHAIN_TYPE_EVM, hex"2105", new bytes(19));
        vm.expectRevert(abi.encodeWithSelector(NonEvmAddress.NonEvmAddressInvalidEvmWidth.selector, uint256(19)));
        harness.parseV1ToBytes32(malformed);
    }

    /// @notice An empty address field (chain-only ERC-7930) is rejected (would right-align to bytes32(0)).
    function test_ParseRevertsOnEmptyAddress() public {
        bytes memory chainOnly = InteroperableAddress.formatEvmV1(8453); // chain reference only, no address
        vm.expectRevert(NonEvmAddress.NonEvmAddressEmpty.selector);
        harness.parseV1ToBytes32(chainOnly);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           FELT252 (STARKNET)
    //////////////////////////////////////////////////////////////////////////*//

    bytes constant SN_MAIN = hex"534e5f4d41494e"; // "SN_MAIN" chain reference (CASA starknet CAIP-350)

    /// @notice The boundary felt FIELD_PRIME - 1 is accepted (strict-less-than range check), and the
    ///         chainType/chainReference pass through the felt down-convert unchanged.
    function test_ParseFeltAcceptsFieldPrimeMinusOne() public view {
        uint256 boundary = NonEvmAddress.FIELD_PRIME - 1;
        bytes memory encoded = NonEvmAddress.formatV1(NonEvmAddress.STARKNET_CHAIN_TYPE, SN_MAIN, bytes32(boundary));
        (bytes2 chainType, bytes memory chainRef, uint256 felt) = harness.parseV1ToFelt252(encoded);
        assertEq(chainType, NonEvmAddress.STARKNET_CHAIN_TYPE, "starknet chainType (0x0003)");
        assertEq(chainRef, SN_MAIN, "UTF-8 chain-id reference preserved");
        assertEq(felt, boundary, "boundary felt accepted verbatim");
    }

    /// @notice A value equal to the Stark field prime is NOT a felt252 and must revert.
    function test_ParseFeltRevertsOnFieldPrime() public {
        bytes memory encoded =
            NonEvmAddress.formatV1(NonEvmAddress.STARKNET_CHAIN_TYPE, SN_MAIN, bytes32(NonEvmAddress.FIELD_PRIME));
        vm.expectRevert(abi.encodeWithSelector(NonEvmAddress.NonEvmAddressNotAFelt.selector, NonEvmAddress.FIELD_PRIME));
        harness.parseV1ToFelt252(encoded);
    }

    /// @notice The zero felt is rejected (no valid Starknet contract lives at 0).
    function test_ParseFeltRevertsOnZeroFelt() public {
        bytes memory encoded = NonEvmAddress.formatV1(NonEvmAddress.STARKNET_CHAIN_TYPE, SN_MAIN, bytes32(0));
        vm.expectRevert(NonEvmAddress.NonEvmAddressZeroFelt.selector);
        harness.parseV1ToFelt252(encoded);
    }

    /// @notice The wrapped bytes32 down-convert rules still apply: a 33-byte address field reverts TooLong.
    function test_ParseFeltRevertsOnAddressTooLong() public {
        bytes memory tooLong = InteroperableAddress.formatV1(NonEvmAddress.STARKNET_CHAIN_TYPE, SN_MAIN, new bytes(33));
        vm.expectRevert(abi.encodeWithSelector(NonEvmAddress.NonEvmAddressTooLong.selector, uint256(33)));
        harness.parseV1ToFelt252(tooLong);
    }

    /// @dev Left-pads a short chain reference into a 32-byte word (helper for the chainId assertion).
    function _padRight(bytes memory b) private pure returns (bytes32 out) {
        assembly {
            out := mload(add(b, 0x20))
        }
    }
}
