// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {RecipePlanLib} from "@lattice-script/lib/RecipePlanLib.sol";
import {RecipeFacet, RecipeSeam} from "@lattice-script/lib/RecipeSpec.sol";
import {Test} from "forge-std/Test.sol";

/// @title RecipePlanLibTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
contract RecipePlanLibTest is Test {
    bytes4 private constant TRANSFER = bytes4(keccak256("transfer(address,uint256)"));
    bytes4 private constant PAUSED = bytes4(keccak256("paused()"));

    function validate(
        RecipeFacet[] memory facets,
        RecipeSeam[] memory seams,
        FacetCut[] memory cuts,
        bytes4[][] memory exports
    ) external pure {
        RecipePlanLib.validateEarly(facets, seams);
        RecipePlanLib.validateCuts(facets, seams, cuts, exports);
    }

    function test_ActiveSeamDoesNotPermitReplacingWithSameFacet() public {
        RecipeFacet[] memory facets = new RecipeFacet[](3);
        facets[0] = RecipePlanLib.all("ERC20");
        facets[1] = RecipePlanLib.all("ERC20Pausable");
        facets[2] = RecipePlanLib.only("ERC20", FacetCutAction.Replace, _one(TRANSFER));
        FacetCut[] memory cuts = new FacetCut[](3);
        cuts[0] = FacetCut(address(1), FacetCutAction.Add, _one(TRANSFER));
        cuts[1] = FacetCut(address(2), FacetCutAction.Add, _one(PAUSED));
        cuts[2] = FacetCut(address(1), FacetCutAction.Replace, _one(TRANSFER));
        bytes4[][] memory exports = new bytes4[][](3);
        exports[0] = _one(TRANSFER);
        exports[1] = _one(PAUSED);
        exports[2] = _one(TRANSFER);
        vm.expectRevert(
            abi.encodeWithSelector(RecipePlanLib.InvalidRecipeCut.selector, "ERC20", TRANSFER, FacetCutAction.Replace)
        );
        this.validate(facets, _seam("ERC20"), cuts, exports);
    }

    function test_DuplicateSelectorInReplaceCutRejectedWithActiveSeam() public {
        RecipeFacet[] memory facets = new RecipeFacet[](2);
        facets[0] = RecipePlanLib.all("ERC20");
        bytes4[] memory repeated = new bytes4[](2);
        repeated[0] = TRANSFER;
        repeated[1] = TRANSFER;
        facets[1] = RecipePlanLib.only("ERC20Pausable", FacetCutAction.Replace, repeated);
        FacetCut[] memory cuts = new FacetCut[](2);
        cuts[0] = FacetCut(address(1), FacetCutAction.Add, _one(TRANSFER));
        cuts[1] = FacetCut(address(2), FacetCutAction.Replace, repeated);
        bytes4[][] memory exports = new bytes4[][](2);
        exports[0] = _one(TRANSFER);
        exports[1] = _one(TRANSFER);
        vm.expectRevert(
            abi.encodeWithSelector(
                RecipePlanLib.InvalidRecipeCut.selector, "ERC20Pausable", TRANSFER, FacetCutAction.Replace
            )
        );
        this.validate(facets, _seam("ERC20Pausable"), cuts, exports);
    }

    function test_DifferentFacetReplacementWithActiveSeamAccepted() public pure {
        RecipeFacet[] memory facets = new RecipeFacet[](2);
        facets[0] = RecipePlanLib.all("ERC20");
        facets[1] = RecipePlanLib.only("ERC20Pausable", FacetCutAction.Replace, _one(TRANSFER));
        FacetCut[] memory cuts = new FacetCut[](2);
        cuts[0] = FacetCut(address(1), FacetCutAction.Add, _one(TRANSFER));
        cuts[1] = FacetCut(address(2), FacetCutAction.Replace, _one(TRANSFER));
        bytes4[][] memory exports = new bytes4[][](2);
        exports[0] = _one(TRANSFER);
        exports[1] = _one(TRANSFER);
        RecipePlanLib.validateEarly(facets, _seam("ERC20Pausable"));
        RecipePlanLib.validateCuts(facets, _seam("ERC20Pausable"), cuts, exports);
    }

    function _one(bytes4 selector) private pure returns (bytes4[] memory values) {
        values = new bytes4[](1);
        values[0] = selector;
    }

    function _seam(string memory owner) private pure returns (RecipeSeam[] memory seams) {
        seams = new RecipeSeam[](1);
        seams[0] =
            RecipePlanLib.seam2("movement", TRANSFER, "ERC20", "ERC20Pausable", owner, "explicit movement ownership");
    }
}
