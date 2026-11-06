// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC4626} from "@lattice-script/base/tokens/DeployERC4626.s.sol";
import {RecipeFacet, RecipeSeam, RecipeSpec, RecipeVariant} from "@lattice-script/lib/RecipeSpec.sol";
import {CanonicalRecipeSeamOracle} from "@lattice-test/composability/RecipeSeamOracleTest.t.sol";
import {ReleasedRecipeGuards} from "@lattice-test/composability/ReleasedRecipeGuards.sol";

/// @title CheckedDeclaredPlanFixture
/// @notice Test-only checked assembly of a deliberately changed plan; production recipes remain fixed.
contract CheckedDeclaredPlanFixture is BaseDeploy {
    function assemble(RecipeFacet[] memory facets, RecipeSeam[] memory seams, address init, bytes memory data)
        external
        returns (address)
    {
        return _assemble(_materialize(facets, seams), init, data);
    }
}

/// @title RecipeSeamCorrelationTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice A correlated wrong cut and allowed-owner declaration cannot change the canonical route oracle.
contract RecipeSeamCorrelationTest is ReleasedRecipeGuards, CanonicalRecipeSeamOracle {
    function assertFixedOracle(address diamond) external view {
        _assertCanonicalSeams(diamond, "DeployERC4626");
    }

    function test_CorrelatedCutAndAllowedOwnerMutationFailsIndependentOracle() public {
        DeployERC4626 recipe = new DeployERC4626();
        (, address init, bytes memory data) = recipe.buildCuts(address(0), "Mutation Vault", "MV", 3);
        RecipeSpec memory spec = recipe.recipeSpec();
        RecipeVariant memory changed = spec.variants[0];
        // Remove the decimals Replace and bless the old ERC20 owner in the data simultaneously.
        // The generic declared-plan checker accepts this coherent alternate plan; it is not canonical.
        RecipeFacet[] memory facets = new RecipeFacet[](changed.facets.length - 1);
        uint256 next;
        for (uint256 i; i < changed.facets.length; ++i) {
            if (i != 3) facets[next++] = changed.facets[i];
        }
        changed.seams[0].allowedOwners[0] = "ERC20";
        address diamond = new CheckedDeclaredPlanFixture().assemble(facets, changed.seams, init, data);
        address oldOwner = _predictedSeamOwner("ERC20");
        address canonicalOwner = _predictedSeamOwner("ERC4626");
        bytes4 decimals = bytes4(keccak256("decimals()"));
        assertEq(IDiamondLoupe(diamond).facetAddress(decimals), oldOwner, "changed declaration really owns proxy route");
        assertTrue(oldOwner != canonicalOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                CanonicalRecipeSeamOracle.WrongCanonicalSeam.selector,
                "DeployERC4626",
                decimals,
                "ERC4626",
                canonicalOwner,
                oldOwner
            )
        );
        this.assertFixedOracle(diamond);
    }

    function test_DroppedParticipantCannotDeactivateFixedCanonicalOracle() public {
        DeployERC4626 recipe = new DeployERC4626();
        (, address init, bytes memory data) = recipe.buildCuts(address(0), "Dropped Vault", "DV", 3);
        RecipeSpec memory spec = recipe.recipeSpec();
        RecipeVariant memory changed = spec.variants[0];
        // Remove both ERC4626 cut entries. Its declared seam is now inactive, but the fixed fixture
        // identity still obliges this topology to route decimals through the canonical vault facet.
        RecipeFacet[] memory facets = new RecipeFacet[](changed.facets.length - 2);
        uint256 next;
        for (uint256 i; i < changed.facets.length; ++i) {
            if (i != 2 && i != 3) facets[next++] = changed.facets[i];
        }
        address diamond = new CheckedDeclaredPlanFixture().assemble(facets, changed.seams, init, data);
        address actual = _predictedSeamOwner("ERC20");
        address canonical = _predictedSeamOwner("ERC4626");
        bytes4 selector = bytes4(keccak256("decimals()"));
        assertEq(IDiamondLoupe(diamond).facetAddress(selector), actual);
        vm.expectRevert(
            abi.encodeWithSelector(
                CanonicalRecipeSeamOracle.WrongCanonicalSeam.selector,
                "DeployERC4626",
                selector,
                "ERC4626",
                canonical,
                actual
            )
        );
        this.assertFixedOracle(diamond);
    }
}
