// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ProposeGovernedCut} from "@lattice-script/governance/ProposeGovernedCut.s.sol";
import {CreateXDeployer} from "@lattice-script/lib/CreateXDeployer.sol";
import {MockCreateX} from "@lattice-test/unit/UpgradeDiamondScriptTest.t.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Smoke test for the {ProposeGovernedCut} Defender-payload script: each entry point returns the
///         proposal TARGET it logs and a `diamondCut(0x1f931c1c)` calldata carrying exactly one
///         single-selector cut with no init.
contract ProposeGovernedCutScriptTest is Test {
    address internal constant DIAMOND = address(0xD1A);
    address internal constant FACET = address(0xFACE7);
    bytes4 internal constant SELECTOR = 0x12345678;

    ProposeGovernedCut internal script;

    function setUp() public {
        vm.etch(address(CreateXDeployer.CREATEX), address(new MockCreateX()).code);
        script = new ProposeGovernedCut();
    }

    function _expected(FacetCutAction action) internal pure returns (bytes memory) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = SELECTOR;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: FACET, action: action, functionSelectors: sels});
        return abi.encodeCall(IGovernedDiamondCut.diamondCut, (cuts, address(0), bytes("")));
    }

    function test_AddSelectorAt_EncodesAddCut() public view {
        assertEq(script.addSelectorAt(DIAMOND, FACET, SELECTOR), _expected(FacetCutAction.Add));
    }

    function test_ReplaceSelectorAt_EncodesReplaceCut() public view {
        assertEq(script.replaceSelectorAt(DIAMOND, FACET, SELECTOR), _expected(FacetCutAction.Replace));
    }

    /// @dev The target is the caller's CreateX CREATE3 diamond address, and it moves with the chain id.
    function test_AddSelector_TargetsPredictedDiamond() public {
        bytes11 entropy = bytes11(uint88(0x0102030405060708090A0B));
        address predicted = CreateXDeployer.predict(CreateXDeployer._guardedSalt(address(this), entropy));

        (address target, bytes memory data) = script.addSelector(entropy, FACET, SELECTOR);
        assertEq(target, predicted, "target != predicted diamond");
        assertEq(data, _expected(FacetCutAction.Add));

        vm.chainId(block.chainid + 1);
        (address otherChainTarget,) = script.addSelector(entropy, FACET, SELECTOR);
        assertTrue(otherChainTarget != target, "target must be chain-bound");
    }
}
