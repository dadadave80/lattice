// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RecipeInitStep} from "@lattice-script/lib/RecipeSpec.sol";
import {RecipeSpecLib} from "@lattice-script/lib/RecipeSpecLib.sol";
import {Test} from "forge-std/Test.sol";

/// @title RecipeSpecLibTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
contract RecipeSpecLibTest is Test {
    function test_WrappingDoesNotReparentCachedInput() public pure {
        RecipeInitStep[] memory leaf = RecipeSpecLib.emptyLeaf("DiamondIntrospectionInit", "initImmutable()");
        RecipeInitStep[][] memory children = new RecipeInitStep[][](1);
        children[0] = leaf;
        RecipeInitStep[] memory first = RecipeSpecLib.wrap(children);
        assertEq(leaf[0].parent, type(uint256).max, "wrapping mutated the leaf root");
        RecipeInitStep[] memory second = RecipeSpecLib.wrap(children);
        assertEq(abi.encode(first), abi.encode(second), "cached leaf changed on reuse");
        assertEq(leaf[0].parent, type(uint256).max, "reuse mutated the leaf root");

        RecipeInitStep[][] memory nested = new RecipeInitStep[][](2);
        nested[0] = first;
        nested[1] = first;
        RecipeInitStep[] memory outer = RecipeSpecLib.wrap(nested);
        assertEq(first[0].parent, type(uint256).max, "wrapping mutated cached subtree root");
        assertEq(first[1].parent, 0, "wrapping mutated cached subtree child");
        assertEq(outer[1].parent, 0);
        assertEq(outer[2].parent, 1);
        assertEq(outer[3].parent, 0);
        assertEq(outer[4].parent, 3);
    }
}
