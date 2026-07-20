// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IReentrancyGuard} from "@lattice/interfaces/security/IReentrancyGuard.sol";
import {ReentrancyGuard} from "@lattice/security/ReentrancyGuard.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Consumer-shape mock: the {ReentrancyGuard} mixin's modifiers over the transient-variant lib.
contract GuardedMock is ReentrancyGuard {
    uint256 public calls;
    bool public enteredMidCall;

    function protectedCall(bool _reenter) external nonReentrant {
        ++calls;
        if (_reenter) GuardedMock(address(this)).protectedCall(false);
    }

    function protectedView() external view nonReadReentrant returns (uint256) {
        return calls;
    }

    /// @dev Read-only reentrancy: a guarded write path calling a `nonReadReentrant` view mid-lock.
    function readReentrancyAttack() external nonReentrant {
        GuardedMock(address(this)).protectedView();
    }

    function captureEnteredState() external nonReentrant {
        enteredMidCall = ReentrancyGuardLib.reentrancyGuardEntered();
    }

    function entered() external view returns (bool) {
        return ReentrancyGuardLib.reentrancyGuardEntered();
    }

    /// @dev Legacy explicit dance — must still lock against the SAME guard the modifier uses.
    function aliasGuardedAttack() external {
        ReentrancyGuardLib.nonReentrantBefore();
        GuardedMock(address(this)).protectedCall(false);
        ReentrancyGuardLib.nonReentrantAfter();
    }
}

contract ReentrancyGuardMixinTest is Test {
    GuardedMock internal mock;

    function setUp() public {
        mock = new GuardedMock();
    }

    // ------------------------------------------------------------------
    // Default chain (sstore branch — block.chainid != 1)
    // ------------------------------------------------------------------

    function test_SequentialCallsSucceed() public {
        mock.protectedCall(false);
        mock.protectedCall(false);
        assertEq(mock.calls(), 2);
    }

    function test_ReentrantCallReverts() public {
        vm.expectRevert(IReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mock.protectedCall(true);
    }

    function test_ReadOnlyReentrancyReverts() public {
        vm.expectRevert(IReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mock.readReentrancyAttack();
    }

    function test_ProtectedViewOutsideGuardSucceeds() public view {
        assertEq(mock.protectedView(), 0);
    }

    function test_EnteredTrueMidCallFalseAfter() public {
        assertFalse(mock.entered());
        mock.captureEnteredState();
        assertTrue(mock.enteredMidCall());
        assertFalse(mock.entered());
    }

    function test_AliasesShareTheModifierGuard() public {
        vm.expectRevert(IReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mock.aliasGuardedAttack();
    }

    function test_LockResetAfterRevert() public {
        vm.expectRevert(IReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mock.protectedCall(true);
        mock.protectedCall(false);
        assertEq(mock.calls(), 1);
    }

    // ------------------------------------------------------------------
    // Mainnet (transient branch — block.chainid == 1)
    // ------------------------------------------------------------------

    function test_Mainnet_SequentialCallsSucceed() public {
        vm.chainId(1);
        mock.protectedCall(false);
        mock.protectedCall(false);
        assertEq(mock.calls(), 2);
    }

    function test_Mainnet_ReentrantCallReverts() public {
        vm.chainId(1);
        vm.expectRevert(IReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mock.protectedCall(true);
    }

    function test_Mainnet_ReadOnlyReentrancyReverts() public {
        vm.chainId(1);
        vm.expectRevert(IReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mock.readReentrancyAttack();
    }

    function test_Mainnet_EnteredTrueMidCallFalseAfter() public {
        vm.chainId(1);
        assertFalse(mock.entered());
        mock.captureEnteredState();
        assertTrue(mock.enteredMidCall());
        assertFalse(mock.entered());
    }

    function test_Mainnet_LockResetAfterRevert() public {
        vm.chainId(1);
        vm.expectRevert(IReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        mock.protectedCall(true);
        mock.protectedCall(false);
        assertEq(mock.calls(), 1);
    }
}
