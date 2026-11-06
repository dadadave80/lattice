// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC3643TestBase} from "@lattice-test/base/ERC3643TestBase.sol";
import {ERC3643TokenPolicyMock} from "@lattice-test/helpers/ERC3643TokenMocks.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IAgentRole} from "@lattice/interfaces/tokens/erc3643/IAgentRole.sol";
import {ICompliance} from "@lattice/interfaces/tokens/erc3643/ICompliance.sol";
import {IERC3643} from "@lattice/interfaces/tokens/erc3643/IERC3643.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";
import {ERC3643InvalidOwner} from "@lattice/tokens/ERC3643/ERC3643Init.sol";
import {ERC3643Params} from "@lattice/tokens/ERC3643/ERC3643Params.sol";

contract ERC3643TokenBoundsTest is ERC3643TestBase {
    function test_AllAgentEntrypointsRejectUnprivilegedCallersIncludingEmptyBatches() public {
        address[] memory wallets = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        bool[] memory freezes = new bool[](0);
        bytes[] memory calls = new bytes[](15);
        calls[0] = abi.encodeCall(IERC3643.mint, (bob, 0));
        calls[1] = abi.encodeCall(IERC3643.burn, (alice, 0));
        calls[2] = abi.encodeCall(IERC3643.forcedTransfer, (alice, bob, 0));
        calls[3] = abi.encodeCall(IERC3643.recoveryAddress, (alice, carol, address(aliceIdentity)));
        calls[4] = abi.encodeCall(IERC3643.pause, ());
        calls[5] = abi.encodeCall(IERC3643.unpause, ());
        calls[6] = abi.encodeCall(IERC3643.setAddressFrozen, (alice, false));
        calls[7] = abi.encodeCall(IERC3643.freezePartialTokens, (alice, 0));
        calls[8] = abi.encodeCall(IERC3643.unfreezePartialTokens, (alice, 0));
        calls[9] = abi.encodeCall(IERC3643.batchForcedTransfer, (wallets, wallets, amounts));
        calls[10] = abi.encodeCall(IERC3643.batchMint, (wallets, amounts));
        calls[11] = abi.encodeCall(IERC3643.batchBurn, (wallets, amounts));
        calls[12] = abi.encodeCall(IERC3643.batchSetAddressFrozen, (wallets, freezes));
        calls[13] = abi.encodeCall(IERC3643.batchFreezePartialTokens, (wallets, amounts));
        calls[14] = abi.encodeCall(IERC3643.batchUnfreezePartialTokens, (wallets, amounts));
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(alice);
            (bool ok, bytes memory reason) = diamond.call(calls[i]);
            assertFalse(ok);
            assertEq(reason, abi.encodeWithSelector(IAgentRole.ERC3643UnauthorizedAgent.selector, alice));
        }
        token.mint(bob, 1); // Reverted unauthorized frames do not strand the transient lock.
        assertEq(token.balanceOf(bob), 101);
    }

    function test_MetadataAndDependencySettersRequireOwner() public {
        bytes[] memory calls = new bytes[](5);
        calls[0] = abi.encodeCall(IERC3643.setName, ("Not owner"));
        calls[1] = abi.encodeCall(IERC3643.setSymbol, ("NO"));
        calls[2] = abi.encodeCall(IERC3643.setOnchainID, (address(aliceIdentity)));
        calls[3] = abi.encodeCall(IERC3643.setIdentityRegistry, (diamond));
        calls[4] = abi.encodeCall(IERC3643.setCompliance, (diamond));
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(alice);
            (bool ok,) = diamond.call(calls[i]);
            assertFalse(ok);
        }
        assertEq(token.name(), "Permissioned");
        assertEq(token.symbol(), "PERM");
        assertEq(token.onchainID(), address(0));
        assertEq(address(token.identityRegistry()), diamond);
        assertEq(address(token.compliance()), diamond);
    }

    function test_SupplyOverflowAndInsufficientBurnRollBackBeforeCallbacks() public {
        ERC3643TokenPolicyMock policy = _externalPolicy();
        token.freezePartialTokens(alice, 1000);
        vm.expectRevert();
        token.mint(bob, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InsufficientBalance.selector, alice, 1000, 1001));
        token.burn(alice, 1001);
        assertEq(token.totalSupply(), 1100);
        assertEq(token.balanceOf(bob), 100);
        assertEq(token.getFrozenTokens(alice), 1000);
        assertEq(policy.creations() + policy.destructions(), 0);
    }

    function test_ZeroValueOperationsStillEmitLifecycleCallbacks() public {
        ERC3643TokenPolicyMock policy = _externalPolicy();
        vm.prank(alice);
        token.transfer(bob, 0);
        token.mint(bob, 0);
        token.burn(alice, 0);
        token.forcedTransfer(alice, bob, 0);
        assertEq(policy.transfers(), 2);
        assertEq(policy.creations(), 1);
        assertEq(policy.destructions(), 1);
        assertEq(token.totalSupply(), 1100);
    }

    function test_ZeroAddressesAreRejectedEvenForZeroMovement() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidReceiver.selector, address(0)));
        token.mint(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidSender.selector, address(0)));
        token.burn(address(0), 0);
        ERC3643Params memory config = _config(false);
        config.owner = address(0);
        vm.expectRevert(ERC3643InvalidOwner.selector);
        this.deployConfig(config);
    }

    function test_MalformedPolicyAndIdentityBooleanRepliesCannotAuthorizeMovement() public {
        bytes[] memory replies = new bytes[](3);
        replies[0] = hex"";
        replies[1] = abi.encode(uint256(2));
        replies[2] = abi.encode(uint256(1), uint256(0));
        for (uint256 i; i < replies.length; ++i) {
            vm.mockCall(diamond, abi.encodeCall(ICompliance.canTransfer, (alice, bob, 1)), replies[i]);
            vm.prank(alice);
            vm.expectRevert(IERC3643.ERC3643ComplianceRejected.selector);
            token.transfer(bob, 1);
            vm.clearMockedCalls();
            vm.mockCall(diamond, abi.encodeCall(IIdentityRegistry.isVerified, (bob)), replies[i]);
            vm.prank(alice);
            vm.expectRevert(abi.encodeWithSelector(IERC3643.ERC3643UnverifiedIdentity.selector, bob));
            token.transfer(bob, 1);
            vm.clearMockedCalls();
        }
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 101);
    }
}
