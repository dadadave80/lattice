// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {ArachnidDeployer} from "@lattice-script/lib/ArachnidDeployer.sol";
import {RecipeGuards} from "@lattice-test/composability/RecipeGuards.sol";
import {ReleasedRecipeGuards} from "@lattice-test/composability/ReleasedRecipeGuards.sol";
import {ArachnidProxy} from "@lattice-test/helpers/ArachnidProxy.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Init} from "@lattice/tokens/ERC20/ERC20Init.sol";

/// @title ReleasedRecipeGuardsTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Negative fixtures prove release checks inspect both actual cuts and the complete initializer tree.
contract ReleasedRecipeGuardsTest is ReleasedRecipeGuards {
    function test_HarnessRejectsUnreleasedFacet() public {
        address facet = address(new ERC20());
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(facet, FacetCutAction.Add, new bytes4[](0));
        vm.expectRevert(abi.encodeWithSelector(UnreleasedRecipeFacet.selector, facet));
        this.checkCuts(cuts);
    }

    function test_HarnessRejectsNestedUnreleasedInitializer() public {
        address leaf = address(new ERC20Init());
        address multi = _released("MultiInit", "MultiInit.sol:MultiInit");
        bytes memory data = _wrap(multi, _wrap(leaf, abi.encodeCall(ERC20Init.init, ("Token", "TOK"))));
        vm.expectRevert(abi.encodeWithSelector(UnreleasedRecipeInitializer.selector, leaf));
        this.checkInitializer(multi, data);
    }

    function test_HarnessAcceptsReleasedNestedInitializer() public {
        address leaf = _released("ERC20Init", "ERC20Init.sol:ERC20Init");
        address multi = _released("MultiInit", "MultiInit.sol:MultiInit");
        _assertReleasedInitializer(multi, _wrap(multi, _wrap(leaf, abi.encodeCall(ERC20Init.init, ("Token", "TOK")))));
    }

    function test_HarnessRejectsWrongMultiInitEntrypoint() public {
        address multi = _released("MultiInit", "MultiInit.sol:MultiInit");
        vm.expectRevert(InvalidRecipeMultiInitCalldata.selector);
        this.checkInitializer(multi, abi.encodeCall(ERC20Init.init, ("Token", "TOK")));
    }

    function checkCuts(FacetCut[] memory cuts) external view {
        _assertReleasedCuts(cuts);
    }

    function checkInitializer(address init, bytes memory data) external view {
        _assertReleasedInitializer(init, data);
    }

    function _released(string memory name, string memory artifact) private returns (address) {
        return ArachnidDeployer.deploy(
            keccak256(abi.encodePacked("lattice.", name, ".", LatticeVersion.VERSION)), vm.getCode(artifact)
        );
    }

    function _wrap(address init, bytes memory data) private pure returns (bytes memory) {
        address[] memory inits = new address[](1);
        inits[0] = init;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;
        return abi.encodeCall(MultiInit.multiInit, (inits, calldatas));
    }
}

/// @title LocalRecipeFallbackTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice No-proxy local tests retain functioning CREATE deployments without claiming release addresses.
contract LocalRecipeFallbackTest is RecipeGuards {
    function test_ImmutableRecipeWithoutArachnid() public {
        vm.etch(ArachnidProxy.PROXY, "");
        (FacetCut[] memory cuts, address init, bytes memory data) = new DeployERC20().buildCuts("Local", "LOC");
        address diamond = _assemble(cuts, init, data);
        assertEq(IERC20(diamond).name(), "Local");
        _assertIntrospectable(diamond, 3);
        _assertImmutableByDesign(diamond);
    }

    function test_AdminRecipeWithoutArachnid() public {
        vm.etch(ArachnidProxy.PROXY, "");
        (FacetCut[] memory cuts, address init, bytes memory data) = new DeployERC20().buildCuts("Local", "LOC", ADMIN);
        address diamond = _assemble(cuts, init, data);
        assertEq(IERC20(diamond).symbol(), "LOC");
        _assertIntrospectable(diamond, 5);
        _assertAdminCanCut(diamond, ADMIN);
    }
}
