// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Base} from "@lattice-test/Base.t.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {InvalidInitialization} from "@lattice/utils/libraries/InitializableLib.sol";

contract AssembleHarness is BaseDeploy {
    LatticeFactory internal injected;

    function inject(LatticeFactory factory) external {
        injected = factory;
    }

    function assemble(FacetCut[] memory cuts, address init, bytes memory initCalldata) external returns (address) {
        return _assemble(cuts, init, initCalldata);
    }

    function currentFactory() external returns (LatticeFactory) {
        return _latticeFactory();
    }

    function _latticeFactory() internal override returns (LatticeFactory) {
        return address(injected) == address(0) ? super._latticeFactory() : injected;
    }
}

contract BaseDeployTest is Base {
    function test_BaseAssemblesAccountThroughSharedDeployScript() public view {
        assertGt(account.code.length, 0, "account diamond not deployed via shared DeployAccount");
        assertEq(DiamondLoupeFacet(account).facetAddresses().length, 9, "canonical 9-facet blueprint not wired");
        assertEq(AccountSigner(account).owner(), owner, "initializer did not run through the deploy path");
    }

    function test_AssembleDeploysAndInitializesThroughFactory() public {
        AssembleHarness harness = new AssembleHarness();
        (FacetCut[] memory cuts, address init, bytes memory data) = _accountRecipe();
        address diamond = harness.assemble(cuts, init, data);

        assertEq(diamond, harness.currentFactory().predict(address(harness), _salt(0)), "not the factory address");
        assertEq(AccountSigner(diamond).owner(), owner, "initializer did not run");
        vm.expectRevert(InvalidInitialization.selector);
        Lattice(payable(diamond)).initialize(cuts, init, data);
    }

    function test_AssembleUsesANewSaltPerDiamond() public {
        AssembleHarness harness = new AssembleHarness();
        (FacetCut[] memory cutsA, address initA, bytes memory dataA) = _accountRecipe();
        (FacetCut[] memory cutsB, address initB, bytes memory dataB) = _accountRecipe();
        address first = harness.assemble(cutsA, initA, dataA);
        address second = harness.assemble(cutsB, initB, dataB);

        assertTrue(first != second, "second diamond reused the first address");
        assertEq(second, harness.currentFactory().predict(address(harness), _salt(1)), "second salt not index 1");
    }

    function test_AssembleRevertsWhenAddressAlreadyDeployed() public {
        AssembleHarness harness = new AssembleHarness();
        LatticeFactory factory = new LatticeFactory(new LatticeRegistry(address(this)), address(0), address(0));
        harness.inject(factory);
        (FacetCut[] memory cuts, address init, bytes memory data) = _accountRecipe();
        vm.prank(address(harness));
        factory.deploy(new RecipeEntry[](0), cuts, init, data, _salt(0));

        (cuts, init, data) = _accountRecipe();
        vm.expectRevert(bytes("BaseDeploy: diamond already deployed for this caller and salt; set a new LATTICE_SALT"));
        harness.assemble(cuts, init, data);
    }

    function test_AssembleUsesOneFactoryPerChain() public {
        AssembleHarness harness = new AssembleHarness();
        LatticeFactory first = harness.currentFactory();
        assertEq(address(harness.currentFactory()), address(first), "factory not reused on the same chain");

        vm.chainId(block.chainid + 1);
        assertTrue(address(harness.currentFactory()) != address(first), "factory reused across chains");
    }

    function _accountRecipe() internal returns (FacetCut[] memory cuts, address init, bytes memory data) {
        AccountInit accountInit;
        (cuts, accountInit) = deployAccount.buildCuts(entryPoint);
        init = address(accountInit);
        data = abi.encodeCall(AccountInit.init, (owner));
    }

    function _salt(uint256 index) internal pure returns (bytes32) {
        return keccak256(abi.encode(bytes32(0), index));
    }
}
