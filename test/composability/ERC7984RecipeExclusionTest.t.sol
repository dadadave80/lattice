// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {RecipePlanLib} from "@lattice-script/lib/RecipePlanLib.sol";
import {RecipeFacet, RecipeSeam} from "@lattice-script/lib/RecipeSpec.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {Test} from "forge-std/Test.sol";

/// @title ERC7984RecipeExclusionTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The checked-recipe rule refusing every facet that calls or signs as the diamond beside ERC7984.
contract ERC7984RecipeExclusionTest is Test {
    function _callers() private pure returns (string[14] memory) {
        return [
            "AccessManager",
            "TimelockController",
            "Governor",
            "ERC7821Executor",
            "ERC7579ModuleConfig",
            "ERC6551Account",
            "ERC6900Executor",
            "AggregatorExecAdapter",
            "HSSAdapter",
            "HSSAdapterRecovery",
            "GovernedDiamondCut",
            "CrosschainTimelockHandler",
            "ERC1271Signature",
            "ERC6900Signature"
        ];
    }

    function validate(RecipeFacet[] memory facets) external pure {
        RecipePlanLib.validateEarly(facets, new RecipeSeam[](0));
    }

    function _plan(string memory a, string memory b) private pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](2);
        facets[0] = RecipePlanLib.all(a);
        facets[1] = RecipePlanLib.all(b);
    }

    function test_RejectsEveryDiamondCallerNextToERC7984() public {
        string[14] memory callers = _callers();
        for (uint256 i; i < 14; ++i) {
            RecipeFacet[] memory forward = _plan("ERC7984", callers[i]);
            RecipeFacet[] memory reverse = _plan(callers[i], "ERC7984");
            vm.expectRevert(
                abi.encodeWithSelector(RecipePlanLib.IncompatibleRecipeFacets.selector, "ERC7984", callers[i])
            );
            this.validate(forward);
            vm.expectRevert(
                abi.encodeWithSelector(RecipePlanLib.IncompatibleRecipeFacets.selector, "ERC7984", callers[i])
            );
            this.validate(reverse);
        }
    }

    function test_AcceptsExternallyGovernedUpgradeLayouts() public view {
        string[5] memory ok =
            ["AccessControlDiamondCut", "SafeDiamondCut", "GovernedSafeDiamondCut", "DiamondCutFacet", "Multicall"];
        for (uint256 i; i < 5; ++i) {
            this.validate(_plan("ERC7984", ok[i]));
        }
    }

    function test_AcceptsMintableLayout() public view {
        // neither facet calls or signs as the diamond
        this.validate(_plan("ERC7984", "ERC7984Mintable"));
        this.validate(_plan("ERC7984", "AccessControl"));
    }

    function test_ExecutorsStillComposeWithoutERC7984() public view {
        this.validate(_plan("Governor", "TimelockController"));
    }

    /// @dev Names and exported selectors: a new facet or a new selector trips it.
    function test_InventoryPinnedForDiamondCallerReview() public {
        (string[] memory names, string[] memory paths) = FacetInventory.inventory();
        assertEq(names.length, 141);
        bytes[] memory sels = new bytes[](names.length);
        for (uint256 i; i < names.length; ++i) {
            sels[i] = IERC8153(deployCode(paths[i])).exportSelectors();
        }
        assertEq(keccak256(abi.encode(names)), 0x9c1b52baa24679744eb450c61245a1e96b6bcdd2822c79d9413e9936e9915b00);
        assertEq(
            keccak256(abi.encode(names, sels)),
            0x16c93afad8c0cf8a313773fc65a657ecd45d04c815138d7bd9d5af08fcd77d8f,
            "facet or selector change: decide whether it calls or signs as the diamond, then update the ERC7984 rule, the deny-list review and this pin"
        );
    }
}
