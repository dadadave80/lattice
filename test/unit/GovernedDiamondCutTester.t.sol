// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IGovernedDiamondCut} from "@lattice/interfaces/IGovernedDiamondCut.sol";
import {Test} from "forge-std/Test.sol";

/// @title GovernedDiamondCutTester
/// @notice Unit tests for the GovernedDiamondCut module.
contract GovernedDiamondCutTester is Test {
    /// @notice The interface exposes exactly one function (`diamondCut`), so its interfaceId
    ///         equals that function's selector — which is the canonical EIP-2535 cut selector
    ///         0x1f931c1c, identical to IDiamondCut. This is intentional: GovernedDiamondCut
    ///         replaces the stock DiamondCutFacet at the same selector.
    function test_InterfaceIdIsCutSelector() public pure {
        assertEq(
            type(IGovernedDiamondCut).interfaceId,
            bytes4(0x1f931c1c),
            "GovernedDiamondCut iface id must be the cut selector"
        );
    }
}
