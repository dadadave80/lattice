// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC3643TestBase} from "@lattice-test/base/ERC3643TestBase.sol";
import {ERC3643TokenIdentityMock, ERC3643TokenPolicyMock} from "@lattice-test/helpers/ERC3643TokenMocks.sol";
import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";
import {IERC3643} from "@lattice/interfaces/tokens/erc3643/IERC3643.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";
import {ERC3643Params} from "@lattice/tokens/ERC3643/ERC3643Params.sol";

contract ERC3643RecoveryTest is ERC3643TestBase {
    function test_RecoveryToNewWalletMovesFreezeStateAndCopiesCountry() public {
        ERC3643TokenPolicyMock policy = _externalPolicy();
        policy.configure(false, true, false);
        token.pause();
        token.setAddressFrozen(alice, true);
        token.freezePartialTokens(alice, 800);
        aliceIdentity.setManagement(carol, true);
        vm.prank(alice);
        token.approve(spender, 99);
        assertTrue(token.recoveryAddress(alice, carol, address(aliceIdentity)));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(carol), 1000);
        assertEq(token.totalSupply(), 1100);
        assertEq(token.getFrozenTokens(alice), 0);
        assertEq(token.getFrozenTokens(carol), 800);
        assertTrue(token.isFrozen(alice));
        assertTrue(token.isFrozen(carol));
        assertFalse(registry.contains(alice));
        assertEq(address(registry.identity(carol)), address(aliceIdentity));
        assertEq(registry.investorCountry(carol), 11);
        assertEq(token.allowance(alice, spender), 99, "old persistent approvals are not enumerable or revoked");
        assertEq(policy.transfers(), 1);
        assertEq(policy.balanceSeen(), 0);
        assertEq(policy.frozenSeen(), 0, "callback observes final recovery freeze accounting");
        vm.expectRevert();
        token.recoveryAddress(alice, bob, address(aliceIdentity));
    }

    function test_SameIdentityTargetKeepsCountryAndCombinesFreezesAndBalances() public {
        aliceIdentity.setManagement(bob, true);
        registry.updateIdentity(bob, IERC3643Identity(address(aliceIdentity)));
        token.freezePartialTokens(alice, 400);
        token.freezePartialTokens(bob, 30);
        token.setAddressFrozen(bob, true);
        vm.prank(bob);
        token.approve(spender, 7);
        token.recoveryAddress(alice, bob, address(aliceIdentity));
        assertEq(token.balanceOf(bob), 1100);
        assertEq(token.getFrozenTokens(bob), 430);
        assertEq(registry.investorCountry(bob), 22, "existing same-identity target keeps its country");
        assertTrue(token.isFrozen(bob));
        assertTrue(token.isFrozen(alice));
        assertEq(token.allowance(bob, spender), 7, "existing target approval is retained");
    }

    function test_ZeroBalanceRecoveryStillMigratesIdentityAndFreezesOldWallet() public {
        _register(spender, aliceIdentity, 33);
        aliceIdentity.setManagement(carol, true);
        token.recoveryAddress(spender, carol, address(aliceIdentity));
        assertEq(token.balanceOf(carol), 0);
        assertEq(registry.investorCountry(carol), 33);
        assertFalse(registry.contains(spender));
        assertTrue(token.isFrozen(spender));
        assertFalse(token.isFrozen(carol));
    }

    function test_RecoveryRejectsInvalidWalletsIdentityAndMissingManagementKey() public {
        vm.expectRevert(abi.encodeWithSelector(IERC3643.ERC3643InvalidRecovery.selector, alice, alice));
        token.recoveryAddress(alice, alice, address(aliceIdentity));
        vm.expectRevert(abi.encodeWithSelector(IERC3643.ERC3643InvalidRecovery.selector, alice, address(0)));
        token.recoveryAddress(alice, address(0), address(aliceIdentity));
        vm.expectRevert();
        token.recoveryAddress(carol, alice, address(aliceIdentity));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC3643.ERC3643RecoveryIdentityMismatch.selector, alice, address(bobIdentity), address(aliceIdentity)
            )
        );
        token.recoveryAddress(alice, carol, address(bobIdentity));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC3643.ERC3643RecoveryIdentityMismatch.selector, bob, address(aliceIdentity), address(bobIdentity)
            )
        );
        token.recoveryAddress(alice, bob, address(aliceIdentity));
        vm.expectRevert(
            abi.encodeWithSelector(IERC3643.ERC3643RecoveryKeyMissing.selector, address(aliceIdentity), carol)
        );
        token.recoveryAddress(alice, carol, address(aliceIdentity));
        assertTrue(registry.contains(alice));
        assertEq(token.balanceOf(alice), 1000);
    }

    function test_RecoveryCallbackFailureRollsBackIdentityLedgerAndFreezes() public {
        ERC3643TokenPolicyMock policy = _externalPolicy();
        policy.configure(true, false, true);
        aliceIdentity.setManagement(carol, true);
        token.freezePartialTokens(alice, 300);
        vm.expectRevert(ERC3643TokenPolicyMock.PolicyFailure.selector);
        token.recoveryAddress(alice, carol, address(aliceIdentity));
        assertTrue(registry.contains(alice));
        assertFalse(registry.contains(carol));
        assertEq(token.balanceOf(alice), 1000);
        assertEq(token.balanceOf(carol), 0);
        assertEq(token.getFrozenTokens(alice), 300);
        assertEq(token.getFrozenTokens(carol), 0);
        assertFalse(token.isFrozen(alice));
        assertEq(policy.transfers(), 0);
    }

    function test_ExternalIdentityRegistryRequiresRealTokenAgentAuthority() public {
        address other = _deploy(_config(false));
        IIdentityRegistry externalRegistry = IIdentityRegistry(other);
        externalRegistry.registerIdentity(alice, IERC3643Identity(address(aliceIdentity)), 11);
        token.setIdentityRegistry(other);
        aliceIdentity.setManagement(carol, true);
        // The EOA owner's role on that registry does not carry across a token CALL.
        vm.expectRevert();
        token.recoveryAddress(alice, carol, address(aliceIdentity));
        assertTrue(externalRegistry.contains(alice));
        assertFalse(externalRegistry.contains(carol));
        // Genuine agent authorization makes the external recovery writes possible.
        (bool granted,) = other.call(abi.encodeWithSignature("addAgent(address)", diamond));
        assertTrue(granted);
        token.recoveryAddress(alice, carol, address(aliceIdentity));
        assertFalse(externalRegistry.contains(alice));
        assertTrue(externalRegistry.contains(carol));
        assertEq(token.balanceOf(carol), 1000);
    }

    function test_CounterfactualExternalStorageBindingRequiredAndHonored() public {
        ERC3643Params memory config = _config(false);
        config.identityStorage = diamond;
        address expected = factory.predict(address(this), bytes32(nonce + 1));
        // A future registry may be bound before code exists, then atomically uses the shared store.
        registry.identityStorage().bindIdentityRegistry(expected);
        address other = _deploy(config);
        assertEq(other, expected);
        IIdentityRegistry externalRegistry = IIdentityRegistry(other);
        externalRegistry.registerIdentity(carol, IERC3643Identity(address(aliceIdentity)), 55);
        assertEq(address(registry.identity(carol)), address(aliceIdentity));
        assertEq(registry.investorCountry(carol), 55);
        // A distinct unbound future registry cannot claim the EOA's binding authority.
        vm.expectRevert();
        this.deployConfig(config);
    }
}
