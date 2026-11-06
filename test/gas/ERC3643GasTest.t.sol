// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {ERC3643TestBase} from "@lattice-test/base/ERC3643TestBase.sol";
import {RegistryIssuerMock} from "@lattice-test/helpers/ERC3643RegistryTestHelpers.sol";
import {TemporaryApprovalActor as Actor} from "@lattice-test/helpers/TemporaryApprovalActor.sol";
import {RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {IERC3643ClaimIssuer} from "@lattice/interfaces/external/erc3643/IERC3643ClaimIssuer.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20TemporaryApproval} from "@lattice/interfaces/tokens/IERC20TemporaryApproval.sol";
import {IClaimTopicsRegistry} from "@lattice/interfaces/tokens/erc3643/IClaimTopicsRegistry.sol";
import {IERC3643} from "@lattice/interfaces/tokens/erc3643/IERC3643.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";
import {ITrustedIssuersRegistry} from "@lattice/interfaces/tokens/erc3643/ITrustedIssuersRegistry.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Real diamond/factory costs for the closed profile; no-claim and one-claim paths are separate.
contract ERC3643GasTest is ERC3643TestBase {
    function test_Gas_TransferAccountAndStorageCold() public {
        address[] memory facets = IDiamondLoupe(diamond).facetAddresses();
        for (uint256 i; i < facets.length; ++i) {
            vm.cool(facets[i]);
        }
        vm.cool(address(bobIdentity));
        vm.cool(diamond);
        vm.prank(alice);
        vm.startSnapshotGas("ERC3643.transfer.explicitCold");
        token.transfer(bob, 10);
        vm.stopSnapshotGas();
    }

    function test_Gas_TransferRepeatedWarm() public {
        vm.prank(alice);
        token.transfer(bob, 10);
        vm.prank(alice);
        vm.startSnapshotGas("ERC3643.transfer.repeatedWarm");
        token.transfer(bob, 10);
        vm.stopSnapshotGas();
    }

    function test_Gas_TransferRegisteredNoRequiredClaims() public {
        vm.prank(alice);
        vm.startSnapshotGas("ERC3643.transfer.noRequiredClaims");
        token.transfer(bob, 10);
        vm.stopSnapshotGas();
    }

    function test_Gas_TransferWithOneRequiredClaim() public {
        RegistryIssuerMock issuer = new RegistryIssuerMock();
        uint256[] memory topics = new uint256[](1);
        topics[0] = 7;
        IClaimTopicsRegistry(diamond).addClaimTopic(7);
        ITrustedIssuersRegistry(diamond).addTrustedIssuer(IERC3643ClaimIssuer(address(issuer)), topics);
        bobIdentity.setClaim(address(issuer), 7, hex"cafe", hex"beef");
        issuer.setSubject(address(bobIdentity), 7);
        vm.prank(alice);
        vm.startSnapshotGas("ERC3643.transfer.oneRequiredClaim");
        token.transfer(bob, 10);
        vm.stopSnapshotGas();
    }

    function test_Gas_TransferFromPersistentAllowance() public {
        vm.prank(alice);
        token.approve(spender, 100);
        vm.prank(spender);
        vm.startSnapshotGas("ERC3643.transferFrom.persistent");
        token.transferFrom(alice, bob, 10);
        vm.stopSnapshotGas();
    }

    function test_Gas_AgentMint() public {
        vm.startSnapshotGas("ERC3643.mint");
        token.mint(bob, 10);
        vm.stopSnapshotGas();
    }

    function test_Gas_AgentBurnFrozenDeficit() public {
        token.freezePartialTokens(alice, 1000);
        vm.startSnapshotGas("ERC3643.burn.frozenDeficit");
        token.burn(alice, 10);
        vm.stopSnapshotGas();
    }

    function test_Gas_AgentForcedTransfer() public {
        token.setAddressFrozen(alice, true);
        token.freezePartialTokens(alice, 1000);
        vm.startSnapshotGas("ERC3643.forcedTransfer.frozenDeficit");
        token.forcedTransfer(alice, bob, 10);
        vm.stopSnapshotGas();
    }

    function test_Gas_RecoveryToNewIdentityWallet() public {
        aliceIdentity.setManagement(carol, true);
        token.freezePartialTokens(alice, 300);
        vm.startSnapshotGas("ERC3643.recovery.newWallet");
        token.recoveryAddress(alice, carol, address(aliceIdentity));
        vm.stopSnapshotGas();
    }

    function test_Gas_AtomicFactoryDeployWithExistingFacetsAndInitializer() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = recipe.buildCuts(_config(false));
        vm.startSnapshotGas("ERC3643.factoryDeploy.existingFacetsAndInit");
        factory.deploy(new RecipeEntry[](0), cuts, init, data, bytes32(++nonce));
        vm.stopSnapshotGas();
    }

    function test_Gas_BatchTransferTwoRecipients() public {
        address[] memory to = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        to[0] = bob;
        to[1] = alice;
        amounts[0] = 10;
        amounts[1] = 20;
        vm.prank(alice);
        vm.startSnapshotGas("ERC3643.batchTransfer.two");
        token.batchTransfer(to, amounts);
        vm.stopSnapshotGas();
    }
}

contract ERC3643GasSpender is Test {
    function spend(IERC3643 token, address owner, string calldata label) external {
        vm.startSnapshotGas("ERC3643TemporaryApproval", label);
        token.transferFrom(owner, address(0xB0B), 10);
        vm.stopSnapshotGas();
    }
}

/// @notice Nested snapshots exclude actor dispatch and the same-transaction temporary grant.
/// forge-config: default.isolate = true
contract ERC3643TemporaryGasTest is ERC3643TestBase {
    Actor internal ownerActor;
    ERC3643GasSpender internal spenderActor;

    function setUp() public override {
        super.setUp();
        diamond = _deploy(_config(true));
        token = IERC3643(diamond);
        registry = IIdentityRegistry(diamond);
        ownerActor = new Actor();
        spenderActor = new ERC3643GasSpender();
        _register(address(ownerActor), aliceIdentity, 11);
        _register(bob, bobIdentity, 22);
        token.mint(address(ownerActor), 100);
        token.unpause();
    }

    function _spend(uint256 temporary, string memory label) internal {
        Actor.Action[] memory approval = new Actor.Action[](1);
        approval[0] = Actor.Action(diamond, abi.encodeCall(IERC20.approve, (address(spenderActor), uint256(20))), false);
        ownerActor.run(approval);
        Actor.Action[] memory actions = new Actor.Action[](2);
        actions[0] = Actor.Action(
            diamond, abi.encodeCall(IERC20TemporaryApproval.temporaryApprove, (address(spenderActor), temporary)), false
        );
        actions[1] = Actor.Action(
            address(spenderActor), abi.encodeCall(ERC3643GasSpender.spend, (token, address(ownerActor), label)), false
        );
        ownerActor.run(actions);
    }

    function test_Gas_TemporaryCovered() public {
        _spend(20, "coveredWarm");
    }

    function test_Gas_TemporaryMixed() public {
        _spend(7, "mixedWarm");
    }
}
