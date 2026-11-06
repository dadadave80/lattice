// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccount} from "@lattice-script/base/accounts/DeployAccount.s.sol";
import {DeployAccount6900} from "@lattice-script/base/accounts/DeployAccount6900.s.sol";
import {DeployERC721} from "@lattice-script/base/tokens/DeployERC721.s.sol";
import {DeployERC721Burnable} from "@lattice-script/base/tokens/DeployERC721Burnable.s.sol";
import {DeployERC721Enumerable} from "@lattice-script/base/tokens/DeployERC721Enumerable.s.sol";
import {RecipePlanLib} from "@lattice-script/lib/RecipePlanLib.sol";
import {
    RecipeInitOutputKind,
    RecipeInitStep,
    RecipeProxyKind,
    RecipeSeam,
    RecipeSpec
} from "@lattice-script/lib/RecipeSpec.sol";
import {RecipeConsistencyGuards} from "@lattice-test/composability/RecipeConsistencyGuards.sol";
import {AccountFactory6900} from "@lattice/accounts/erc6900/AccountFactory6900.sol";
import {AccountInit6900} from "@lattice/accounts/erc6900/AccountInit6900.sol";
import {AccountFactory} from "@lattice/accounts/erc7579/AccountFactory.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";
import {Test} from "forge-std/Test.sol";

/// @title RecipeConsistencyMutationHarness
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice External test boundaries expose the actual consistency checks and canonical factory assembly.
contract RecipeConsistencyMutationHarness is RecipeConsistencyGuards {
    function assembleSingle(FacetCut[] memory cuts, address init, bytes memory data, RecipeSpec memory spec)
        external
        returns (address)
    {
        _expectRecipe(spec, 0, "DeployERC721");
        return _assemble(cuts, init, data);
    }

    function assembleParallel(
        FacetCut[] memory cuts,
        address[] memory inits,
        bytes[] memory data,
        RecipeSpec memory spec,
        string memory fixedRecipe
    ) external returns (address) {
        _expectRecipe(spec, 0, fixedRecipe);
        return _assembleMulti(cuts, inits, data);
    }

    function assembleAccount(
        FacetCut[] memory cuts,
        address init,
        RecipeSpec memory spec,
        bool modular,
        address entryPoint
    ) external returns (address) {
        _expectRecipe(spec, 0, modular ? "DeployAccount6900" : "DeployAccount");
        _assertReleasedAccount(modular, entryPoint, cuts, init);
        _assertAccountRecipe(cuts, modular);
        if (modular) return new AccountFactory6900(cuts, init).createAccount(msg.sender, bytes32(0));
        return new AccountFactory(cuts, init).createAccount(msg.sender, bytes32(0));
    }
}

/// @title RecipeConsistencyMutationTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Actual canonical builders pass unchanged; independent cut/tree/shape mutations fail specific guards.
/// @dev Parameter bindings remain descriptions. These tests do not evaluate them or infer argument values.
contract RecipeConsistencyMutationTest is Test {
    struct SingleFixture {
        FacetCut[] cuts;
        address init;
        bytes data;
        RecipeSpec spec;
    }

    struct ParallelFixture {
        FacetCut[] cuts;
        address[] inits;
        bytes[] data;
        RecipeSpec spec;
    }

    struct AccountFixture {
        FacetCut[] cuts;
        address init;
        RecipeSpec spec;
    }

    RecipeConsistencyMutationHarness private _harness;
    address private constant ENTRY_POINT = address(0xE117);

    function setUp() public {
        _harness = new RecipeConsistencyMutationHarness();
    }

    function test_Control_UnchangedSingleBuilderAssembles() public {
        SingleFixture memory f = _single();
        address diamond = _harness.assembleSingle(f.cuts, f.init, f.data, f.spec);
        assertGt(diamond.code.length, 0);
        assertEq(IERC721(diamond).name(), "Consistency NFT");
        assertTrue(IDiamondLoupe(diamond).facetAddress(IERC721.balanceOf.selector) != address(0));
    }

    function test_Control_UnchangedNestedParallelBuilderAssembles() public {
        ParallelFixture memory f = _burnable();
        address diamond = _harness.assembleParallel(f.cuts, f.inits, f.data, f.spec, "DeployERC721Burnable");
        assertGt(diamond.code.length, 0);
        assertEq(IERC721(diamond).name(), "Consistency NFT");
        assertTrue(IDiamondLoupe(diamond).facetAddress(bytes4(keccak256("burn(uint256)"))) != address(0));
    }

    function test_Control_UnchangedExceptAndOnlyBuilderAssembles() public {
        ParallelFixture memory f = _enumerable();
        address diamond = _harness.assembleParallel(f.cuts, f.inits, f.data, f.spec, "DeployERC721Enumerable");
        assertGt(diamond.code.length, 0);
        assertEq(IERC721(diamond).name(), "Consistency NFT");
        assertTrue(IDiamondLoupe(diamond).facetAddress(bytes4(keccak256("tokenByIndex(uint256)"))) != address(0));
    }

    function test_Control_UnchangedAccountDiamondAssembles() public {
        _assertAccountControl(false);
    }

    function test_Control_UnchangedModularAccountAssembles() public {
        _assertAccountControl(true);
    }

    function test_RejectsChangedCutOrder() public {
        SingleFixture memory f = _single();
        FacetCut memory first = abi.decode(abi.encode(f.cuts[0]), (FacetCut));
        f.cuts[0] = f.cuts[1];
        f.cuts[1] = first;
        _rejectSingle(f, "recipe cut facet");
    }

    function test_RejectsChangedCutAction() public {
        SingleFixture memory f = _single();
        f.cuts[1].action = FacetCutAction.Replace;
        _rejectSingle(f, "recipe cut action");
    }

    function test_RejectsMissingExceptSelectionView() public {
        ParallelFixture memory f = _enumerable();
        assertEq(f.cuts[3].functionSelectors.length, 3, "control: three additive enumeration views");
        bytes4[] memory shortened = new bytes4[](2);
        shortened[0] = f.cuts[3].functionSelectors[0];
        shortened[1] = f.cuts[3].functionSelectors[1];
        f.cuts[3].functionSelectors = shortened;
        _rejectParallel(f, "DeployERC721Enumerable", "recipe selector selection/order");
    }

    function test_RejectsChangedOnlySelectorOrder() public {
        ParallelFixture memory f = _enumerable();
        assertEq(f.cuts[4].functionSelectors.length, 3, "control: three replacement transfers");
        (f.cuts[4].functionSelectors[0], f.cuts[4].functionSelectors[1]) =
        (f.cuts[4].functionSelectors[1], f.cuts[4].functionSelectors[0]);
        _rejectParallel(f, "DeployERC721Enumerable", "recipe selector selection/order");
    }

    function test_RejectsChangedNestedInitParent() public {
        ParallelFixture memory f = _burnable();
        assertEq(f.spec.variants[0].initPlan[2].parent, 1, "control: ERC721 init belongs to nested base");
        f.spec.variants[0].initPlan[2].parent = 0;
        _rejectParallel(f, "DeployERC721Burnable", "initializer parent/order");
    }

    function test_RejectsChangedNestedInitOrder() public {
        ParallelFixture memory f = _burnable();
        RecipeInitStep memory first = abi.decode(abi.encode(f.spec.variants[0].initPlan[2]), (RecipeInitStep));
        f.spec.variants[0].initPlan[2] = f.spec.variants[0].initPlan[3];
        f.spec.variants[0].initPlan[3] = first;
        _rejectParallel(f, "DeployERC721Burnable", "initializer identity/order");
    }

    function test_RejectsExtraDeclaredInitNode() public {
        ParallelFixture memory f = _burnable();
        RecipeInitStep[] memory original = f.spec.variants[0].initPlan;
        RecipeInitStep[] memory extended = new RecipeInitStep[](original.length + 1);
        for (uint256 i; i < original.length; ++i) {
            extended[i] = original[i];
        }
        extended[original.length] = original[original.length - 1];
        f.spec.variants[0].initPlan = extended;
        _rejectParallel(f, "DeployERC721Burnable", "extra declared init nodes");
    }

    function test_RejectsMissingDeclaredInitNode() public {
        ParallelFixture memory f = _burnable();
        RecipeInitStep[] memory original = f.spec.variants[0].initPlan;
        RecipeInitStep[] memory shortened = new RecipeInitStep[](original.length - 1);
        for (uint256 i; i < shortened.length; ++i) {
            shortened[i] = original[i];
        }
        f.spec.variants[0].initPlan = shortened;
        _rejectParallel(f, "DeployERC721Burnable", "missing declared init node");
    }

    function test_RejectsChangedInitSignature() public {
        ParallelFixture memory f = _burnable();
        f.spec.variants[0].initPlan[2].signature = "init(string)";
        _rejectParallel(f, "DeployERC721Burnable", "initializer function signature");
    }

    function test_RejectsConstructorBoundNodeInOrdinaryRecipe() public {
        ParallelFixture memory f = _burnable();
        f.spec.variants[0].initPlan[2].constructorBound = true;
        _rejectParallel(f, "DeployERC721Burnable", "ordinary recipe cannot use constructor-bound init");
    }

    function test_RejectsSingleShapeForParallelBuilder() public {
        ParallelFixture memory f = _burnable();
        f.spec.variants[0].initOutputKind = RecipeInitOutputKind.Single;
        _rejectParallel(f, "DeployERC721Burnable", "builder initializer output shape");
    }

    function test_RejectsWrongAccountDiamondKind() public {
        _assertWrongAccountKind(false, "assertion failed: 0 != 1");
    }

    function test_RejectsWrongModularAccountKind() public {
        _assertWrongAccountKind(true, "assertion failed: 0 != 2");
    }

    function test_RejectsUnboundAccountDiamondInitializer() public {
        _assertUnboundAccount(false);
    }

    function test_RejectsUnboundModularAccountInitializer() public {
        _assertUnboundAccount(true);
    }

    function test_RejectsActiveSeamWithoutIndependentFixedOracleRow() public {
        SingleFixture memory f = _single();
        f.spec.variants[0].seams = new RecipeSeam[](1);
        f.spec.variants[0].seams[0] = RecipePlanLib.seam2(
            "unreviewed-row",
            IERC721.balanceOf.selector,
            "ERC721",
            "ERC165Facet",
            "ERC721",
            "fixture-only additional active seam"
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                RecipeConsistencyGuards.MissingIndependentSeamOracle.selector,
                "DeployERC721",
                IERC721.balanceOf.selector
            )
        );
        _harness.assembleSingle(f.cuts, f.init, f.data, f.spec);
    }

    function test_RejectsSpecDroppingRequiredExclusionAndReplaceSeams() public {
        ParallelFixture memory f = _enumerable();
        f.spec.variants[0].seams = new RecipeSeam[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                RecipePlanLib.UndeclaredRecipeSeam.selector,
                "ERC721Enumerable",
                bytes4(keccak256("transferFrom(address,address,uint256)"))
            )
        );
        _harness.assembleParallel(f.cuts, f.inits, f.data, f.spec, "DeployERC721Enumerable");
    }

    function _single() private returns (SingleFixture memory f) {
        DeployERC721 recipe = new DeployERC721();
        (f.cuts, f.init, f.data) = recipe.buildCuts("Consistency NFT", "CNFT");
        f.spec = recipe.recipeSpec();
    }

    function _burnable() private returns (ParallelFixture memory f) {
        DeployERC721Burnable recipe = new DeployERC721Burnable();
        (f.cuts, f.inits, f.data) = recipe.buildCuts("Consistency NFT", "CNFT");
        f.spec = recipe.recipeSpec();
    }

    function _enumerable() private returns (ParallelFixture memory f) {
        DeployERC721Enumerable recipe = new DeployERC721Enumerable();
        (f.cuts, f.inits, f.data) = recipe.buildCuts("Consistency NFT", "CNFT");
        f.spec = recipe.recipeSpec();
    }

    function _account(bool modular) private returns (AccountFixture memory f) {
        if (modular) {
            DeployAccount6900 recipe = new DeployAccount6900();
            (FacetCut[] memory cuts, AccountInit6900 init) = recipe.buildCuts(ENTRY_POINT);
            f.cuts = cuts;
            f.init = address(init);
            f.spec = recipe.recipeSpec();
        } else {
            DeployAccount recipe = new DeployAccount();
            (FacetCut[] memory cuts, AccountInit init) = recipe.buildCuts(ENTRY_POINT);
            f.cuts = cuts;
            f.init = address(init);
            f.spec = recipe.recipeSpec();
        }
    }

    function _assertAccountControl(bool modular) private {
        AccountFixture memory f = _account(modular);
        address diamond = _harness.assembleAccount(f.cuts, f.init, f.spec, modular, ENTRY_POINT);
        assertGt(diamond.code.length, 0);
        assertEq(IDiamondLoupe(diamond).facetAddresses().length, modular ? 10 : 9);
    }

    function _assertWrongAccountKind(bool modular, string memory expected) private {
        AccountFixture memory f = _account(modular);
        f.spec.variants[0].proxyKind = RecipeProxyKind.Lattice;
        (bool ok, bytes memory reason) = address(_harness)
            .call(
                abi.encodeCall(
                    RecipeConsistencyMutationHarness.assembleAccount, (f.cuts, f.init, f.spec, modular, ENTRY_POINT)
                )
            );
        _assertAssertionFailure(ok, reason, expected, true);
    }

    function _assertUnboundAccount(bool modular) private {
        AccountFixture memory f = _account(modular);
        f.spec.variants[0].initPlan[0].constructorBound = false;
        (bool ok, bytes memory reason) = address(_harness)
            .call(
                abi.encodeCall(
                    RecipeConsistencyMutationHarness.assembleAccount, (f.cuts, f.init, f.spec, modular, ENTRY_POINT)
                )
            );
        _assertAssertionFailure(ok, reason, "assertion failed", true);
    }

    function _rejectSingle(SingleFixture memory f, string memory diagnostic) private {
        (bool ok, bytes memory reason) = address(_harness)
            .call(abi.encodeCall(RecipeConsistencyMutationHarness.assembleSingle, (f.cuts, f.init, f.data, f.spec)));
        _assertAssertionFailure(ok, reason, diagnostic, false);
    }

    function _rejectParallel(ParallelFixture memory f, string memory fixedRecipe, string memory diagnostic) private {
        (bool ok, bytes memory reason) = address(_harness)
            .call(
                abi.encodeCall(
                    RecipeConsistencyMutationHarness.assembleParallel, (f.cuts, f.inits, f.data, f.spec, fixedRecipe)
                )
            );
        _assertAssertionFailure(ok, reason, diagnostic, false);
    }

    function _assertAssertionFailure(bool ok, bytes memory reason, string memory diagnostic, bool exact) private pure {
        assertFalse(ok, "mutation unexpectedly passed consistency guard");
        assertGe(reason.length, 4, "mutation failed without an assertion reason");
        // The pinned Foundry VM wraps assertion diagnostics in CheatcodeError(string).
        assertEq(
            bytes4(reason), bytes4(keccak256("CheatcodeError(string)")), "mutation failed outside assertion boundary"
        );
        bytes memory args = new bytes(reason.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = reason[i + 4];
        }
        string memory message = abi.decode(args, (string));
        if (exact) {
            assertEq(message, diagnostic, "unexpected unlabeled assertion");
        } else {
            assertTrue(_hasDiagnostic(message, diagnostic), string.concat("wrong assertion guard: ", message));
        }
    }

    function _hasDiagnostic(string memory text, string memory expected) private pure returns (bool) {
        bytes memory value = bytes(text);
        bytes memory needle = bytes(expected);
        if (value.length < needle.length) return false;
        for (uint256 i; i < needle.length; ++i) {
            if (value[i] != needle[i]) return false;
        }
        return value.length == needle.length || value[needle.length] == bytes1(":");
    }
}
