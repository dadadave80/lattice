// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {Base} from "@lattice-test/Base.t.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {LatticeDeployer} from "@lattice/LatticeDeployer.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {InvalidInitialization} from "@lattice/utils/libraries/InitializableLib.sol";

contract RevertingLatticeInit {
    function init() external pure {
        revert("init failed");
    }
}

/// @notice Proves the shared-deploy pattern end-to-end: {Base}.setUp composes the account through the SAME
///         {DeployAccount} blueprint production uses, so a passing assertion here means test setup and the
///         deploy path cannot silently diverge (a facet added to/removed from the canonical blueprint moves
///         this count and fails the test).
contract BaseDeployTest is Base {
    function test_BaseAssemblesAccountThroughSharedDeployScript() public view {
        assertGt(account.code.length, 0, "account diamond not deployed via shared DeployAccount");
        assertEq(DiamondLoupeFacet(account).facetAddresses().length, 9, "canonical 9-facet blueprint not wired");
        assertEq(AccountSigner(account).owner(), owner, "initializer did not run through the deploy path");
    }

    function test_LatticeDeployerInitializesBeforeReturningProxy() public {
        (FacetCut[] memory cuts, AccountInit init) = deployAccount.buildCuts(entryPoint);
        Lattice diamond = Lattice(
            payable(new LatticeDeployer().deploy(cuts, address(init), abi.encodeCall(AccountInit.init, (owner))))
        );

        assertEq(AccountSigner(address(diamond)).owner(), owner, "deployer did not initialize owner");
        vm.expectRevert(InvalidInitialization.selector);
        diamond.initialize(cuts, address(init), abi.encodeCall(AccountInit.init, (owner)));
    }

    function test_LatticeDeployerRollsBackProxyWhenInitializationFails() public {
        LatticeDeployer atomicDeployer = new LatticeDeployer();
        address predicted = vm.computeCreateAddress(address(atomicDeployer), vm.getNonce(address(atomicDeployer)));
        RevertingLatticeInit revertingInit = new RevertingLatticeInit();

        vm.expectRevert("init failed");
        atomicDeployer.deploy(new FacetCut[](0), address(revertingInit), abi.encodeCall(RevertingLatticeInit.init, ()));

        assertEq(predicted.code.length, 0, "failed initialization left a proxy deployed");
    }
}
