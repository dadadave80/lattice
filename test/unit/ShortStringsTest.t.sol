// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ShortString, ShortStrings} from "@lattice/utils/libraries/ShortStrings.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Holds storage fallbacks needed for withFallback tests
contract ShortStringsHarness {
    using ShortStrings for *;

    string public fallbackStore;

    function toShortStringWithFallback(string memory value) external returns (ShortString) {
        return ShortStrings.toShortStringWithFallback(value, fallbackStore);
    }

    function toStringWithFallback(ShortString value) external view returns (string memory) {
        return ShortStrings.toStringWithFallback(value, fallbackStore);
    }

    function toShortString(string memory s) external pure returns (ShortString) {
        return ShortStrings.toShortString(s);
    }

    function byteLength(ShortString sstr) external pure returns (uint256) {
        return ShortStrings.byteLength(sstr);
    }
}

contract ShortStringsTest is Test {
    using ShortStrings for *;

    ShortStringsHarness harness;

    function setUp() public {
        harness = new ShortStringsHarness();
    }

    // -------------------------------------------------------------------------
    // Pack / unpack roundtrip for various lengths
    // -------------------------------------------------------------------------

    function test_RoundtripEmpty() public pure {
        string memory s = "";
        ShortString packed = ShortStrings.toShortString(s);
        assertEq(ShortStrings.byteLength(packed), 0);
        assertEq(ShortStrings.toString(packed), s);
    }

    function test_RoundtripSingleChar() public pure {
        string memory s = "A";
        ShortString packed = ShortStrings.toShortString(s);
        assertEq(ShortStrings.byteLength(packed), 1);
        assertEq(ShortStrings.toString(packed), s);
    }

    function test_RoundtripShortString() public pure {
        string memory s = "Hello, World!";
        ShortString packed = ShortStrings.toShortString(s);
        assertEq(ShortStrings.byteLength(packed), 13);
        assertEq(ShortStrings.toString(packed), s);
    }

    function test_RoundtripMediumString() public pure {
        string memory s = "abcdefghijklmnopqrstuvwxy"; // 25 chars
        ShortString packed = ShortStrings.toShortString(s);
        assertEq(ShortStrings.byteLength(packed), 25);
        assertEq(ShortStrings.toString(packed), s);
    }

    // -------------------------------------------------------------------------
    // Exact 31-byte string roundtrips
    // -------------------------------------------------------------------------

    function test_Roundtrip31Bytes() public pure {
        string memory s = "1234567890123456789012345678901"; // exactly 31 chars
        assertEq(bytes(s).length, 31, "test setup: should be 31 bytes");
        ShortString packed = ShortStrings.toShortString(s);
        assertEq(ShortStrings.byteLength(packed), 31);
        assertEq(ShortStrings.toString(packed), s);
    }

    // -------------------------------------------------------------------------
    // 32-byte string reverts StringTooLong
    // -------------------------------------------------------------------------

    function test_32ByteReverts() public {
        string memory s = "12345678901234567890123456789012"; // exactly 32 chars
        assertEq(bytes(s).length, 32, "test setup: should be 32 bytes");
        vm.expectRevert(abi.encodeWithSelector(ShortStrings.StringTooLong.selector, s));
        harness.toShortString(s);
    }

    function test_LongStringReverts() public {
        string memory s = "This string is definitely longer than thirty-one bytes total";
        vm.expectRevert(abi.encodeWithSelector(ShortStrings.StringTooLong.selector, s));
        harness.toShortString(s);
    }

    // -------------------------------------------------------------------------
    // Fallback to storage for long strings
    // -------------------------------------------------------------------------

    function test_FallbackForLongString() public {
        string memory longStr = "This is exactly thirty-two bytes!"; // 33 chars
        ShortString result = harness.toShortStringWithFallback(longStr);

        // The returned ShortString should be the sentinel (fallback indicator)
        // We can't read the raw sentinel from outside, but toStringWithFallback should work
        string memory recovered = harness.toStringWithFallback(result);
        assertEq(recovered, longStr);
    }

    function test_FallbackForShortString() public {
        string memory shortStr = "Short";
        ShortString result = harness.toShortStringWithFallback(shortStr);
        string memory recovered = harness.toStringWithFallback(result);
        assertEq(recovered, shortStr);
        // Also verify byteLength works (not the sentinel)
        assertEq(ShortStrings.byteLength(result), 5);
    }

    function test_FallbackRoundtrip31Bytes() public {
        string memory s = "abcdefghijklmnopqrstuvwxyz12345"; // 31 bytes
        assertEq(bytes(s).length, 31);
        ShortString result = harness.toShortStringWithFallback(s);
        string memory recovered = harness.toStringWithFallback(result);
        assertEq(recovered, s);
        assertEq(ShortStrings.byteLength(result), 31);
    }

    function test_FallbackRoundtrip32Bytes() public {
        string memory s = "abcdefghijklmnopqrstuvwxyz123456"; // 32 bytes
        assertEq(bytes(s).length, 32);
        ShortString result = harness.toShortStringWithFallback(s);
        string memory recovered = harness.toStringWithFallback(result);
        assertEq(recovered, s);
    }

    // -------------------------------------------------------------------------
    // InvalidShortString on sentinel
    // -------------------------------------------------------------------------

    function test_InvalidShortStringReverts() public {
        // The sentinel ShortString should revert byteLength
        ShortString sentinel = ShortString.wrap(bytes32(type(uint256).max));
        vm.expectRevert(ShortStrings.InvalidShortString.selector);
        harness.byteLength(sentinel);
    }
}
