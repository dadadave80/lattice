// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {DeployERC20Pausable} from "@lattice-script/base/tokens/DeployERC20Pausable.s.sol";
import {DeployERC20Votes} from "@lattice-script/base/tokens/DeployERC20Votes.s.sol";
import {ArachnidDeployer} from "@lattice-script/lib/ArachnidDeployer.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {InitInventory} from "@lattice-script/lib/InitInventory.sol";
import {RecipePlanLib} from "@lattice-script/lib/RecipePlanLib.sol";
import {RecipeFacet} from "@lattice-script/lib/RecipeSpec.sol";
import {ArachnidProxy} from "@lattice-test/helpers/ArachnidProxy.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {Test} from "forge-std/Test.sol";

function withERC1363(RecipeFacet[] memory base) pure returns (RecipeFacet[] memory) {
    RecipeFacet[] memory extension = new RecipeFacet[](1);
    extension[0] = RecipePlanLib.all("ERC1363");
    return RecipePlanLib.append(base, extension);
}

contract PausableWithERC1363 is DeployERC20Pausable {
    function _cutPlan(uint256 variant) internal pure override returns (RecipeFacet[] memory) {
        return withERC1363(super._cutPlan(variant));
    }

    function plan() external pure returns (RecipeFacet[] memory) {
        return _cutPlan(0);
    }

    function attempt(bool resolveBeforeValidation) external returns (address) {
        if (resolveBeforeValidation) _facet("ERC165Facet");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            buildCuts("Checked", "CHK", address(0xAD));
        return _assembleMulti(cuts, inits, data);
    }
}

contract VotesWithERC1363 is DeployERC20Votes {
    function _cutPlan(uint256 variant) internal pure override returns (RecipeFacet[] memory) {
        return withERC1363(super._cutPlan(variant));
    }

    function plan() external pure returns (RecipeFacet[] memory) {
        return _cutPlan(0);
    }

    function attempt() external returns (address) {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            buildCuts("Checked", "CHK", address(0xAD));
        return _assembleMulti(cuts, inits, data);
    }
}

contract GovernedVaultWithERC1363 is DeployGovernedVault {
    function _cutPlan(uint256 variant) internal pure override returns (RecipeFacet[] memory) {
        return withERC1363(super._cutPlan(variant));
    }

    function plan() external pure returns (RecipeFacet[] memory) {
        return _cutPlan(0);
    }

    function attempt(GovernedVaultParams memory params) external returns (address) {
        (FacetCut[] memory cuts, address init, bytes memory data) = buildCuts(params);
        return _assemble(cuts, init, data);
    }
}

/// @title CheckedRecipeCompositionTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Real checked builders reject known callback/mover bypasses before resolving any shared implementation.
contract CheckedRecipeCompositionTest is Test {
    error ResolutionSentinel();

    function setUp() public {
        vm.etch(ArachnidProxy.PROXY, ArachnidProxy.RUNTIME);
    }

    function test_RejectsERC1363PausableBeforeSharedResolution() public {
        PausableWithERC1363 recipe = new PausableWithERC1363();
        _installResolutionSentinel(recipe.plan());
        vm.expectRevert(
            abi.encodeWithSelector(RecipePlanLib.IncompatibleRecipeFacets.selector, "ERC1363", "ERC20Pausable")
        );
        recipe.attempt(false);
    }

    function test_RejectsERC1363VotesBeforeSharedResolution() public {
        VotesWithERC1363 recipe = new VotesWithERC1363();
        _installResolutionSentinel(recipe.plan());
        vm.expectRevert(
            abi.encodeWithSelector(RecipePlanLib.IncompatibleRecipeFacets.selector, "ERC1363", "ERC20Votes")
        );
        recipe.attempt();
    }

    function test_RejectsERC1363GovernedVaultBeforeSharedResolution() public {
        GovernedVaultWithERC1363 recipe = new GovernedVaultWithERC1363();
        _installResolutionSentinel(recipe.plan());
        GovernedVaultParams memory params;
        params.name = "Checked";
        params.symbol = "CHK";
        params.votingPeriod = 600;
        vm.expectRevert(
            abi.encodeWithSelector(RecipePlanLib.IncompatibleRecipeFacets.selector, "ERC1363", "GovernedVault")
        );
        recipe.attempt(params);
    }

    function test_ResolutionSentinelDetectsAnActuallyLateGuard() public {
        PausableWithERC1363 recipe = new PausableWithERC1363();
        _installResolutionSentinel(recipe.plan());
        // ArachnidDeployer deliberately wraps a failing proxy call; this is distinct from the expected policy error.
        vm.expectRevert(abi.encodeWithSignature("Error(string)", "ArachnidDeployer: proxy deployment reverted"));
        recipe.attempt(true);
    }

    function _installResolutionSentinel(RecipeFacet[] memory plan) private {
        (string[] memory names, string[] memory paths) = FacetInventory.inventory();
        for (uint256 i; i < plan.length; ++i) {
            bool found;
            for (uint256 j; j < names.length; ++j) {
                if (keccak256(bytes(names[j])) != keccak256(bytes(plan[i].name))) continue;
                assertEq(_prediction(names[j], paths[j]).code.length, 0, "facet resolution could skip sentinel");
                found = true;
                break;
            }
            assertTrue(found, "test plan references an unknown facet");
        }
        (names, paths) = InitInventory.inventory();
        for (uint256 i; i < names.length; ++i) {
            assertEq(_prediction(names[i], paths[i]).code.length, 0, "init resolution could skip sentinel");
        }
        vm.mockCallRevert(ArachnidProxy.PROXY, bytes(""), abi.encodeWithSelector(ResolutionSentinel.selector));
    }

    function _prediction(string memory name, string memory artifact) private view returns (address) {
        return ArachnidDeployer.predict(
            keccak256(abi.encodePacked("lattice.", name, ".", LatticeVersion.VERSION)), keccak256(vm.getCode(artifact))
        );
    }
}
