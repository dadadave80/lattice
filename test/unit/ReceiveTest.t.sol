// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {Receive} from "@lattice/Receive.sol";
import {Test} from "forge-std/Test.sol";

/// @title ReceiveTest
/// @notice Proves bare-ETH acceptance is a FACET concern: a diamond cut with {Receive} under the zero
///         selector accepts plain sends through the fallback's `selectorToFacet(0x00000000)` route, and a
///         diamond without it rejects them — `LatticeDiamond` itself no longer declares `receive()`.
contract ReceiveTest is Test {
    LatticeDiamond internal bare;
    LatticeDiamond internal receiving;

    function setUp() public {
        bare = new LatticeDiamond();
        bare.initialize(new FacetCut[](0), address(0), "");

        FacetCut[] memory cuts = new FacetCut[](1);
        bytes4[] memory sel = new bytes4[](1);
        sel[0] = bytes4(0);
        cuts[0] = FacetCut({facetAddress: address(new Receive()), action: FacetCutAction.Add, functionSelectors: sel});
        receiving = new LatticeDiamond();
        receiving.initialize(cuts, address(0), "");
    }

    function test_BareSendAcceptedWithReceiveFacet() public {
        (bool ok,) = address(receiving).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(receiving).balance, 1 ether);
    }

    function test_BareSendRejectedWithoutReceiveFacet() public {
        (bool ok,) = address(bare).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(bare).balance, 0);
    }

    function test_ExplicitZeroSelectorCalldataRejected() public {
        // 4 bytes of 0x00000000 route to the facet but are NOT empty calldata — receive() must not run.
        (bool ok,) = address(receiving).call{value: 1 ether}(hex"00000000");
        assertFalse(ok);
    }

    function test_ShortNonEmptyCalldataRejected() public {
        // 1-3 zero bytes still read as msg.sig 0x00000000 and reach the facet, but calldata is non-empty.
        (bool ok,) = address(receiving).call{value: 1 ether}(hex"00");
        assertFalse(ok);
    }

    function test_ExportSelectorsIsTheZeroSelector() public {
        Receive r = new Receive();
        assertEq(r.exportSelectors(), hex"00000000");
    }
}
