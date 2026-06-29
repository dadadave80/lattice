// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    NonCanonicalEncoding,
    SegmentOutOfOrder,
    SparseCalldataSegmentLib,
    ValidationSignatureSegmentMissing
} from "@lattice/accounts/erc6900/libraries/SparseCalldataSegmentLib.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Calldata harness (the lib operates on `bytes calldata`).
contract Harness {
    using SparseCalldataSegmentLib for bytes;

    function advance(bytes calldata s, uint8 i) external pure returns (bytes memory body, bytes memory rem) {
        (bytes calldata b, bytes calldata r) = s.advanceSegmentIfAtIndex(i);
        return (b, r);
    }

    function finalSeg(bytes calldata s) external pure returns (bytes memory) {
        return s.getFinalSegment();
    }

    function idx(bytes calldata s) external pure returns (uint8) {
        return s.getIndex();
    }
}

contract SparseCalldataSegmentLibTester is Test {
    Harness h;

    function setUp() public {
        h = new Harness();
    }

    /// @dev Segment 0 (body 0xaaaa), segment 1 omitted, segment 2 (body 0xbb), final 0xFF segment ("final").
    function _blob() internal pure returns (bytes memory) {
        return abi.encodePacked(
            uint8(0), uint32(2), bytes2(0xaaaa), uint8(2), uint32(1), bytes1(0xbb), uint8(0xff), bytes("final")
        );
    }

    function test_GetIndex() public view {
        assertEq(h.idx(_blob()), 0, "leading index");
        assertEq(h.idx(abi.encodePacked(uint8(0xff), bytes("x"))), 0xff, "final index");
    }

    function test_FullWalk() public view {
        bytes memory blob = _blob();

        (bytes memory b0, bytes memory r0) = h.advance(blob, 0);
        assertEq(b0, hex"aaaa", "segment 0 body");

        // index 1 omitted → empty body, cursor unchanged
        (bytes memory b1, bytes memory r1) = h.advance(r0, 1);
        assertEq(b1.length, 0, "omitted segment is empty");
        assertEq(r1, r0, "cursor unchanged when index skipped");

        (bytes memory b2, bytes memory r2) = h.advance(r1, 2);
        assertEq(b2, hex"bb", "segment 2 body");

        assertEq(h.finalSeg(r2), bytes("final"), "final segment");
    }

    function test_RevertSegmentOutOfOrder() public {
        // leading index 0 < requested 5
        vm.expectRevert(SegmentOutOfOrder.selector);
        h.advance(_blob(), 5);
    }

    function test_RevertNonCanonicalEncoding() public {
        // a present segment (index 0) with zero-length body
        bytes memory bad = abi.encodePacked(uint8(0), uint32(0));
        vm.expectRevert(NonCanonicalEncoding.selector);
        h.advance(bad, 0);
    }

    function test_RevertFinalSegmentMissing() public {
        // final segment must lead with 0xFF
        bytes memory notFinal = abi.encodePacked(uint8(0x03), bytes("x"));
        vm.expectRevert(ValidationSignatureSegmentMissing.selector);
        h.finalSeg(notFinal);
    }
}
