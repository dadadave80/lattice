// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {ArachnidDeployer} from "@lattice-script/lib/ArachnidDeployer.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {InitInventory} from "@lattice-script/lib/InitInventory.sol";
import {RecipePlanLib} from "@lattice-script/lib/RecipePlanLib.sol";
import {
    RecipeFacet,
    RecipeInitOutputKind,
    RecipeInitStep,
    RecipeProxyKind,
    RecipeSeam,
    RecipeSelectorSelection,
    RecipeSpec,
    RecipeVariant
} from "@lattice-script/lib/RecipeSpec.sol";
import {ExpectedRecipeRoute, RecipeSeamExpectations} from "@lattice-test/composability/RecipeSeamExpectations.sol";
import {CanonicalRecipeSeamOracle} from "@lattice-test/composability/RecipeSeamOracleTest.t.sol";
import {ReleasedRecipeGuards} from "@lattice-test/composability/ReleasedRecipeGuards.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";

/// @title RecipeConsistencyGuards
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Compare every typed canonical builder fixture with its data, then observe real proxy seam routes.
/// @dev Literal fixture names also feed a separate source-ledger oracle, independent of declared allowedOwners.
abstract contract RecipeConsistencyGuards is ReleasedRecipeGuards, CanonicalRecipeSeamOracle {
    error MissingIndependentSeamOracle(string recipe, bytes4 selector);

    bytes private _expectedVariant;
    string private _canonicalRecipe;
    bool private _parallelAssembly;
    mapping(string => address) private _facetAddresses;
    mapping(string => address) private _initAddresses;

    constructor() {
        (string[] memory names, string[] memory artifacts) = FacetInventory.inventory();
        for (uint256 i; i < names.length; ++i) {
            _facetAddresses[names[i]] = _at(names[i], artifacts[i]);
        }
        (names, artifacts) = InitInventory.inventory();
        for (uint256 i; i < names.length; ++i) {
            _initAddresses[names[i]] = _at(names[i], artifacts[i]);
        }
    }

    function _at(string memory name, string memory artifact) private view returns (address) {
        return ArachnidDeployer.predict(
            keccak256(abi.encodePacked("lattice.", name, ".", LatticeVersion.VERSION)), keccak256(vm.getCode(artifact))
        );
    }

    function _expectRecipe(RecipeSpec memory spec, uint256 variant, string memory fixedRecipeName) internal {
        assertEq(spec.name, fixedRecipeName, "fixture recipe identity");
        assertLt(variant, spec.variants.length, "missing typed variant");
        _assertIndependentOracleCoverage(spec.variants[variant], fixedRecipeName);
        _expectedVariant = abi.encode(spec.variants[variant]);
        _canonicalRecipe = fixedRecipeName;
    }

    function _assertIndependentOracleCoverage(RecipeVariant memory variant, string memory fixedRecipeName)
        private
        pure
    {
        ExpectedRecipeRoute[] memory fixedRoutes = RecipeSeamExpectations.forRecipe(fixedRecipeName);
        for (uint256 i; i < variant.seams.length; ++i) {
            RecipeSeam memory seam = variant.seams[i];
            bool active = true;
            for (uint256 j; j < seam.participants.length; ++j) {
                if (!RecipePlanLib.contains(variant.facets, seam.participants[j])) active = false;
            }
            if (!active) continue;
            bool covered;
            for (uint256 j; j < fixedRoutes.length; ++j) {
                if (fixedRoutes[j].selector == seam.selector) covered = true;
            }
            if (!covered) revert MissingIndependentSeamOracle(fixedRecipeName, seam.selector);
        }
    }

    function _assertRecipeCuts(FacetCut[] memory actual, RecipeVariant memory expected) internal view {
        assertEq(actual.length, expected.facets.length, "recipe ordered cut count");
        bytes4[][] memory exports = new bytes4[][](actual.length);
        for (uint256 i; i < actual.length; ++i) {
            RecipeFacet memory declaration = expected.facets[i];
            address owner = _facetAddresses[declaration.name];
            assertTrue(owner != address(0), "unknown declared facet");
            assertEq(actual[i].facetAddress, owner, "recipe cut facet");
            assertEq(uint256(actual[i].action), uint256(declaration.action), "recipe cut action");
            bytes memory packed = IERC8153(owner).exportSelectors();
            require(packed.length % 4 == 0, "invalid facet export");
            bytes4[] memory exported = new bytes4[](packed.length / 4);
            for (uint256 j; j < exported.length; ++j) {
                bytes4 selector;
                assembly ("memory-safe") { selector := mload(add(add(packed, 32), mul(j, 4))) }
                exported[j] = selector;
            }
            exports[i] = exported;
            bytes4[] memory selectors;
            if (declaration.selection == RecipeSelectorSelection.All) {
                selectors = exported;
            } else if (declaration.selection == RecipeSelectorSelection.Only) {
                selectors = declaration.selectors;
            } else {
                uint256 count;
                for (uint256 j; j < exported.length; ++j) {
                    if (!_has(declaration.selectors, exported[j])) ++count;
                }
                selectors = new bytes4[](count);
                count = 0;
                for (uint256 j; j < exported.length; ++j) {
                    if (!_has(declaration.selectors, exported[j])) selectors[count++] = exported[j];
                }
            }
            assertEq(abi.encode(actual[i].functionSelectors), abi.encode(selectors), "recipe selector selection/order");
        }
        // Validate the spec's own declarations too: a builder may be correct while its metadata drops a seam.
        RecipePlanLib.validateEarly(expected.facets, expected.seams);
        RecipePlanLib.validateCuts(expected.facets, expected.seams, actual, exports);
    }

    function _has(bytes4[] memory values, bytes4 value) private pure returns (bool) {
        for (uint256 i; i < values.length; ++i) {
            if (values[i] == value) return true;
        }
        return false;
    }

    function _assertRecipeInit(
        RecipeInitStep[] memory plan,
        uint256 cursor,
        uint256 parent,
        address at,
        bytes memory data
    ) private view returns (uint256 next) {
        assertLt(cursor, plan.length, "missing declared init node");
        RecipeInitStep memory node = plan[cursor];
        assertEq(node.parent, parent, "initializer parent/order");
        assertFalse(node.constructorBound, "ordinary recipe cannot use constructor-bound init");
        assertEq(at, _initAddresses[node.name], "initializer identity/order");
        assertTrue(at != address(0), "unknown declared initializer");
        assertGe(data.length, 4, "initializer calldata selector missing");
        assertEq(bytes4(data), bytes4(keccak256(bytes(node.signature))), "initializer function signature");
        next = cursor + 1;
        if (RecipePlanLib.equal(node.name, "MultiInit")) {
            assertEq(node.signature, "multiInit(address[],bytes[])");
            bytes memory args = new bytes(data.length - 4);
            for (uint256 i; i < args.length; ++i) {
                args[i] = data[i + 4];
            }
            (address[] memory children, bytes[] memory calls) = abi.decode(args, (address[], bytes[]));
            assertEq(children.length, calls.length, "parallel init arrays");
            for (uint256 i; i < children.length; ++i) {
                next = _assertRecipeInit(plan, next, cursor, children[i], calls[i]);
            }
        }
    }

    function _assertDeclaredSeams(address diamond, RecipeVariant memory variant) private view {
        for (uint256 i; i < variant.seams.length; ++i) {
            RecipeSeam memory seam = variant.seams[i];
            bool active = true;
            for (uint256 j; j < seam.participants.length; ++j) {
                if (!RecipePlanLib.contains(variant.facets, seam.participants[j])) active = false;
            }
            if (!active) continue;
            address actual = IDiamondLoupe(diamond).facetAddress(seam.selector);
            if (actual == address(0) && seam.allowUnrouted) continue;
            assertTrue(actual != address(0), "active seam route missing");
            bool allowed;
            for (uint256 j; j < seam.allowedOwners.length; ++j) {
                if (_facetAddresses[seam.allowedOwners[j]] == actual) allowed = true;
            }
            assertTrue(allowed, "active seam owner differs from declaration");
        }
    }

    function _assemble(FacetCut[] memory cuts, address init, bytes memory data)
        internal
        override
        returns (address diamond)
    {
        assertGt(_expectedVariant.length, 0, "typed fixture must register its recipe spec");
        RecipeVariant memory variant = abi.decode(_expectedVariant, (RecipeVariant));
        assertEq(uint256(variant.proxyKind), uint256(RecipeProxyKind.Lattice), "ordinary proxy kind");
        assertEq(
            uint256(variant.initOutputKind),
            uint256(_parallelAssembly ? RecipeInitOutputKind.Parallel : RecipeInitOutputKind.Single),
            "builder initializer output shape"
        );
        _assertRecipeCuts(cuts, variant);
        assertEq(
            _assertRecipeInit(variant.initPlan, 0, type(uint256).max, init, data),
            variant.initPlan.length,
            "extra declared init nodes"
        );
        diamond = super._assemble(cuts, init, data);
        _assertDeclaredSeams(diamond, variant);
        _assertCanonicalSeams(diamond, _canonicalRecipe);
    }

    function _assembleMulti(FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls)
        internal
        override
        returns (address diamond)
    {
        _parallelAssembly = true;
        diamond = super._assembleMulti(cuts, inits, calls);
        _parallelAssembly = false;
    }

    function _assertAccountRecipe(FacetCut[] memory cuts, bool modular) internal view {
        assertGt(_expectedVariant.length, 0, "account fixture must register its spec");
        RecipeVariant memory variant = abi.decode(_expectedVariant, (RecipeVariant));
        _assertRecipeCuts(cuts, variant);
        assertEq(uint256(variant.initOutputKind), uint256(RecipeInitOutputKind.Account));
        assertEq(
            uint256(variant.proxyKind),
            uint256(modular ? RecipeProxyKind.ModularAccount6900 : RecipeProxyKind.AccountDiamond)
        );
        assertEq(variant.initPlan.length, 1);
        assertTrue(variant.initPlan[0].constructorBound);
        assertEq(variant.initPlan[0].name, modular ? "AccountInit6900" : "AccountInit");
        assertEq(variant.initPlan[0].signature, "init(address)");
        assertEq(variant.initPlan[0].constructorParameters.length, 1);
        assertEq(variant.initPlan[0].constructorParameters[0].name, "entryPoint_");
        assertEq(variant.initPlan[0].constructorParameters[0].abiType, "address");
    }
}
