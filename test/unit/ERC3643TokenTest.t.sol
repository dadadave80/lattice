// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {OwnableFacet} from "@diamond/facets/OwnableFacet.sol";
import {ERC3643TestBase} from "@lattice-test/base/ERC3643TestBase.sol";
import {ERC3643TokenPolicyMock} from "@lattice-test/helpers/ERC3643TokenMocks.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IAgentRole} from "@lattice/interfaces/tokens/erc3643/IAgentRole.sol";
import {IERC3643} from "@lattice/interfaces/tokens/erc3643/IERC3643.sol";
import {ERC3643ExecutionInProgress} from "@lattice/tokens/ERC3643/libraries/ERC3643ExecutionLib.sol";

contract ERC3643TokenTest is ERC3643TestBase {
    function test_CanonicalFactoryStartsPausedAndBindsLocalComponents() public {
        IERC3643 fresh = IERC3643(_deploy(_config(false)));
        assertTrue(fresh.paused());
        assertEq(fresh.name(), "Permissioned");
        assertEq(fresh.symbol(), "PERM");
        assertEq(fresh.decimals(), 6);
        assertEq(fresh.version(), LatticeVersion.VERSION);
        assertEq(fresh.onchainID(), address(0));
        assertEq(address(fresh.identityRegistry()), address(fresh));
        assertEq(address(fresh.compliance()), address(fresh));
        assertEq(fresh.compliance().getTokenBound(), address(fresh));
        assertTrue(IAgentRole(address(fresh)).isAgent(address(this)));
        assertTrue(ERC165Facet(address(fresh)).supportsInterface(type(IERC3643).interfaceId));
        assertTrue(ERC165Facet(address(fresh)).supportsInterface(type(IERC20).interfaceId));
        assertTrue(ERC165Facet(address(fresh)).supportsInterface(bytes4(0x7f5828d0)), "routed ERC173 ownership");
        assertFalse(ERC165Facet(address(fresh)).supportsInterface(bytes4(0x1f931c1c)));
        vm.prank(alice);
        vm.expectRevert(IERC3643.ERC3643TokenPaused.selector);
        fresh.transfer(bob, 0);
    }

    function test_TransferAndTransferFromSharePolicyAndAllowance() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 30));
        vm.prank(alice);
        token.approve(spender, 60);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 40));
        assertEq(token.balanceOf(alice), 930);
        assertEq(token.balanceOf(bob), 170);
        assertEq(token.allowance(alice, spender), 20);
        assertEq(token.totalSupply(), 1100);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InsufficientAllowance.selector, spender, 20, 21));
        token.transferFrom(alice, bob, 21);
    }

    function test_OnlyRecipientNeedsVerifiedIdentityAndZeroTransfersStillCheckPolicy() public {
        registry.deleteIdentity(alice);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC3643.ERC3643UnverifiedIdentity.selector, carol));
        token.transfer(carol, 0);
        ERC3643TokenPolicyMock policy = _externalPolicy();
        policy.configure(false, false, false);
        vm.prank(alice);
        vm.expectRevert(IERC3643.ERC3643ComplianceRejected.selector);
        token.transfer(bob, 0);
    }

    function test_PauseAndEitherFullFreezeRejectEvenApprovedSpend() public {
        vm.prank(alice);
        token.approve(spender, 10);
        token.pause();
        vm.prank(spender);
        vm.expectRevert(IERC3643.ERC3643TokenPaused.selector);
        token.transferFrom(alice, bob, 1);
        // Approvals remain useful during an operational pause or wallet freeze.
        vm.prank(alice);
        token.approve(spender, 20);
        token.unpause();
        token.setAddressFrozen(alice, true);
        vm.prank(spender);
        vm.expectRevert(abi.encodeWithSelector(IERC3643.ERC3643WalletFrozen.selector, alice));
        token.transferFrom(alice, bob, 1);
        token.setAddressFrozen(alice, false);
        token.setAddressFrozen(bob, true);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC3643.ERC3643WalletFrozen.selector, bob));
        token.transfer(bob, 1);
        assertEq(token.allowance(alice, spender), 20);
    }

    function test_PartialFreezeRestrictsOrdinarySpendAndUnfreezeBounds() public {
        token.freezePartialTokens(alice, 800);
        vm.prank(alice);
        token.transfer(bob, 200);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC3643.ERC3643InsufficientFreeBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
        token.unfreezePartialTokens(alice, 100);
        assertEq(token.getFrozenTokens(alice), 700);
        vm.expectRevert(abi.encodeWithSelector(IERC3643.ERC3643InsufficientFrozenTokens.selector, alice, 700, 701));
        token.unfreezePartialTokens(alice, 701);
        vm.expectRevert(abi.encodeWithSelector(IERC3643.ERC3643InsufficientFreeBalance.selector, alice, 100, 101));
        token.freezePartialTokens(alice, 101);
    }

    function test_AgentOperationsBypassOrdinaryPolicyButAlwaysCallLifecycle() public {
        ERC3643TokenPolicyMock policy = _externalPolicy();
        policy.configure(false, true, false);
        token.pause();
        token.setAddressFrozen(alice, true);
        token.setAddressFrozen(bob, true);
        token.freezePartialTokens(alice, 900);
        token.mint(bob, 25);
        assertTrue(token.forcedTransfer(alice, bob, 250));
        assertEq(token.getFrozenTokens(alice), 750); // Deficit only, not a blanket thaw.
        registry.deleteIdentity(alice);
        token.burn(alice, 50); // Burn needs no investor identity.
        assertEq(token.getFrozenTokens(alice), 700);
        assertEq(token.balanceOf(alice), 700);
        assertEq(token.balanceOf(bob), 375);
        assertEq(token.totalSupply(), 1075);
        assertEq(policy.creations(), 1);
        assertEq(policy.transfers(), 1);
        assertEq(policy.destructions(), 1);
        assertEq(policy.balanceSeen(), 700);
        assertEq(policy.frozenSeen(), 700);
        vm.expectRevert(abi.encodeWithSelector(IERC3643.ERC3643UnverifiedIdentity.selector, carol));
        token.forcedTransfer(alice, carol, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC3643.ERC3643UnverifiedIdentity.selector, carol));
        token.mint(carol, 1);
    }

    function test_CallbackFailureRollsBackAllAccountingAndAllowance() public {
        ERC3643TokenPolicyMock policy = _externalPolicy();
        policy.configure(true, false, true);
        vm.prank(alice);
        token.approve(spender, 50);
        vm.prank(spender);
        vm.expectRevert(ERC3643TokenPolicyMock.PolicyFailure.selector);
        token.transferFrom(alice, bob, 30);
        assertEq(token.allowance(alice, spender), 50);
        token.freezePartialTokens(alice, 1000);
        vm.expectRevert(ERC3643TokenPolicyMock.PolicyFailure.selector);
        token.burn(alice, 50);
        vm.expectRevert(ERC3643TokenPolicyMock.PolicyFailure.selector);
        token.forcedTransfer(alice, bob, 50);
        vm.expectRevert(ERC3643TokenPolicyMock.PolicyFailure.selector);
        token.mint(bob, 50);
        assertEq(token.balanceOf(alice), 1000);
        assertEq(token.balanceOf(bob), 100);
        assertEq(token.totalSupply(), 1100);
        assertEq(token.getFrozenTokens(alice), 1000);
        assertEq(policy.transfers() + policy.creations() + policy.destructions(), 0);
    }

    function test_CallbackCannotReenterEvenAsAnAuthorizedAgentOrOwner() public {
        ERC3643TokenPolicyMock policy = _externalPolicy();
        IAgentRole(diamond).addAgent(address(policy));
        bytes[] memory attempts = new bytes[](8);
        attempts[0] = abi.encodeCall(IERC3643.mint, (bob, 1));
        attempts[1] = abi.encodeCall(IERC3643.burn, (alice, 1));
        attempts[2] = abi.encodeCall(IERC3643.forcedTransfer, (alice, bob, 1));
        attempts[3] = abi.encodeCall(IERC3643.recoveryAddress, (alice, carol, address(aliceIdentity)));
        attempts[4] = abi.encodeCall(IERC3643.pause, ());
        attempts[5] = abi.encodeCall(IERC3643.setAddressFrozen, (bob, true));
        attempts[6] = abi.encodeCall(IERC3643.setIdentityRegistry, (diamond));
        attempts[7] = abi.encodeCall(IAgentRole.addAgent, (carol));
        for (uint256 i; i < attempts.length; ++i) {
            policy.setReentry(diamond, attempts[i]);
            vm.prank(alice);
            token.transfer(bob, 1);
            assertFalse(policy.reentrySucceeded());
            assertEq(bytes4(policy.reentryResult()), ERC3643ExecutionInProgress.selector);
        }
        assertEq(policy.transfers(), attempts.length);
        assertEq(token.balanceOf(alice), 1000 - attempts.length);
        assertFalse(token.paused());
        assertFalse(token.isFrozen(bob));
    }

    function test_MetadataAndComponentAdministrationFollowCurrentOwner() public {
        token.setName("Updated");
        token.setSymbol("UPD");
        token.setOnchainID(address(aliceIdentity));
        assertEq(token.name(), "Updated");
        assertEq(token.symbol(), "UPD");
        assertEq(token.onchainID(), address(aliceIdentity));
        OwnableFacet(diamond).transferOwnership(bob);
        vm.expectRevert();
        token.setName("Old owner");
        vm.prank(bob);
        token.setName("New owner");
        assertEq(token.name(), "New owner");
        assertTrue(IAgentRole(diamond).isAgent(address(this)));
        assertFalse(IAgentRole(diamond).isAgent(bob));
        vm.prank(bob);
        IAgentRole(diamond).removeAgent(address(this));
        vm.expectRevert();
        token.pause();
    }

    function test_ExternalComplianceHandshakeIsAtomicAndDoesNotImpersonateOwner() public {
        ERC3643TokenPolicyMock policy = new ERC3643TokenPolicyMock(address(this));
        // Unbound and owner-controlled means the token cannot bind on the owner's behalf.
        vm.expectRevert();
        token.setCompliance(address(policy));
        assertEq(address(token.compliance()), diamond);
        assertEq(token.compliance().getTokenBound(), diamond);
        policy.bindToken(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC3643.ERC3643ComplianceBinding.selector, address(policy), bob));
        token.setCompliance(address(policy));
        policy.unbindToken(bob);
        policy.bindToken(diamond);
        token.setCompliance(address(policy));
        vm.expectRevert();
        token.setCompliance(diamond); // External old owner must authorize the unbind.
        assertEq(address(token.compliance()), address(policy));
        policy.unbindToken(diamond); // Out-of-band old binding clear is supported.
        token.setCompliance(diamond);
        assertEq(token.compliance().getTokenBound(), diamond);
        policy.setOwner(diamond);
        token.setCompliance(address(policy)); // Token now genuinely has binding authority.
        assertEq(policy.getTokenBound(), diamond);
        token.setCompliance(diamond);
        assertEq(policy.getTokenBound(), address(0));
    }

    function test_BatchTransferIsScalarEquivalentAndFailureAtomic() public {
        ERC3643TokenPolicyMock policy = _externalPolicy();
        address[] memory to = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        to[0] = bob;
        to[1] = carol;
        amounts[0] = 5;
        amounts[1] = 7;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC3643.ERC3643UnverifiedIdentity.selector, carol));
        token.batchTransfer(to, amounts);
        assertEq(token.balanceOf(alice), 1000);
        assertEq(policy.transfers(), 0);
        to[1] = bob;
        vm.prank(alice);
        token.batchTransfer(to, amounts);
        assertEq(token.balanceOf(bob), 112);
        assertEq(policy.transfers(), 2);
    }

    function test_AllAgentBatchesUseScalarRulesAndCallbacks() public {
        ERC3643TokenPolicyMock policy = _externalPolicy();
        address[] memory wallets = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        bool[] memory freezes = new bool[](2);
        wallets[0] = alice;
        wallets[1] = bob;
        amounts[0] = 10;
        amounts[1] = 20;
        freezes[0] = true;
        freezes[1] = true;
        token.pause();
        token.batchSetAddressFrozen(wallets, freezes);
        token.batchFreezePartialTokens(wallets, amounts);
        token.batchMint(wallets, amounts);
        token.batchBurn(wallets, amounts); // Burn deliberately ignores ordinary pause/freeze checks.
        token.batchUnfreezePartialTokens(wallets, amounts);
        address[] memory to = new address[](2);
        to[0] = bob;
        to[1] = alice;
        token.batchForcedTransfer(wallets, to, amounts);
        assertEq(token.balanceOf(alice), 1010);
        assertEq(token.balanceOf(bob), 90);
        assertTrue(token.isFrozen(alice));
        assertEq(token.getFrozenTokens(alice), 0);
        assertEq(policy.creations(), 2);
        assertEq(policy.destructions(), 2);
        assertEq(policy.transfers(), 2);
    }

    function test_AllBatchLengthsAreValidatedBeforeEffects() public {
        address[] memory wallets = new address[](1);
        uint256[] memory amounts = new uint256[](0);
        bool[] memory freezes = new bool[](0);
        bytes[] memory calls = new bytes[](7);
        calls[0] = abi.encodeCall(IERC3643.batchTransfer, (wallets, amounts));
        calls[1] = abi.encodeCall(IERC3643.batchForcedTransfer, (wallets, wallets, amounts));
        calls[2] = abi.encodeCall(IERC3643.batchMint, (wallets, amounts));
        calls[3] = abi.encodeCall(IERC3643.batchBurn, (wallets, amounts));
        calls[4] = abi.encodeCall(IERC3643.batchSetAddressFrozen, (wallets, freezes));
        calls[5] = abi.encodeCall(IERC3643.batchFreezePartialTokens, (wallets, amounts));
        calls[6] = abi.encodeCall(IERC3643.batchUnfreezePartialTokens, (wallets, amounts));
        for (uint256 i; i < calls.length; ++i) {
            (bool ok, bytes memory result) = diamond.call(calls[i]);
            assertFalse(ok);
            assertEq(bytes4(result), IERC3643.ERC3643InvalidArrayLengths.selector);
        }
    }

    function testFuzz_FrozenBalanceRemainsBoundedAfterPrivilegedSpend(uint256 frozen, uint256 amount, bool burn_)
        public
    {
        frozen = bound(frozen, 0, 1000);
        amount = bound(amount, 0, 1000);
        token.freezePartialTokens(alice, frozen);
        if (burn_) token.burn(alice, amount);
        else token.forcedTransfer(alice, bob, amount);
        uint256 remaining = 1000 - amount;
        assertEq(token.getFrozenTokens(alice), frozen > remaining ? remaining : frozen);
        assertLe(token.getFrozenTokens(alice), token.balanceOf(alice));
    }
}
