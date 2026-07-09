// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {InvariantCheckerTestBase} from "@lattice-test/base/InvariantCheckerTestBase.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IInvariantChecker} from "@lattice/interfaces/security/IInvariantChecker.sol";
import {InvariantChecker} from "@lattice/security/InvariantChecker.sol";

// -------------------------------------------------------------------------
// Helper contracts — simple invariant implementations
// -------------------------------------------------------------------------

/// @notice Always returns true. Used to test passing invariant checks.
contract AlwaysTrueInvariant {
    function alwaysTrue() external pure returns (bool) {
        return true;
    }
}

/// @notice Always returns false. Used to test failing invariant checks.
contract AlwaysFalseInvariant {
    function alwaysFalse() external pure returns (bool) {
        return false;
    }
}

/// @notice Always reverts. Used to test staticcall failure scenarios.
contract RevertingInvariant {
    function alwaysReverts() external pure returns (bool) {
        revert("always reverts");
    }
}

/// @title InvariantCheckerTest
/// @notice Exercises the InvariantChecker registry facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployInvariantChecker} script (see {InvariantCheckerTestBase}) — every registry call below routes
///         through the diamond's `delegatecall` dispatch, not a flattened inheritance mock. Admin gating on
///         registration is enforced by the cut-in `AccessControl` facet; `supportsInterface` by the cut-in
///         `ERC165Facet`.
contract InvariantCheckerTest is InvariantCheckerTestBase {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 private constant KEY_TRUE = keccak256("KEY_TRUE");
    bytes32 private constant KEY_FALSE = keccak256("KEY_FALSE");
    bytes32 private constant KEY_REVERT = keccak256("KEY_REVERT");
    bytes32 private constant KEY_UNREGISTERED = keccak256("KEY_UNREGISTERED");

    AlwaysTrueInvariant internal trueInv;
    AlwaysFalseInvariant internal falseInv;
    RevertingInvariant internal revertInv;

    address internal admin = address(0xA1);
    address internal nonAdmin = address(0xB2);

    function setUp() public {
        diamond = _deployInvariantChecker(admin);
        checker = InvariantChecker(diamond);

        trueInv = new AlwaysTrueInvariant();
        falseInv = new AlwaysFalseInvariant();
        revertInv = new RevertingInvariant();
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    function test_ERC165RegisteredIInvariantChecker() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IInvariantChecker).interfaceId));
    }

    // -------------------------------------------------------------------------
    // registerInvariant — access control
    // -------------------------------------------------------------------------

    function test_RegisterByNonAdminReverts() public {
        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, DEFAULT_ADMIN_ROLE
            )
        );
        checker.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);
    }

    // -------------------------------------------------------------------------
    // registerInvariant — zero target
    // -------------------------------------------------------------------------

    function test_RegisterWithZeroTargetReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantInvalidTarget.selector));
        checker.registerInvariant(KEY_TRUE, address(0), AlwaysTrueInvariant.alwaysTrue.selector);
    }

    // -------------------------------------------------------------------------
    // registerInvariant — happy path
    // -------------------------------------------------------------------------

    function test_RegisterStoresValues() public {
        vm.prank(admin);
        checker.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        (address t, bytes4 sel) = checker.getInvariant(KEY_TRUE);
        assertEq(t, address(trueInv));
        assertEq(sel, AlwaysTrueInvariant.alwaysTrue.selector);
    }

    function test_RegisterEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IInvariantChecker.InvariantRegistered(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);
        checker.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);
    }

    // -------------------------------------------------------------------------
    // registerInvariant — overwrite existing
    // -------------------------------------------------------------------------

    function test_RegisterInvariantOverwritesSilently() public {
        vm.prank(admin);
        checker.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        // Overwrite with a different target — should succeed silently and update the entry.
        vm.prank(admin);
        checker.registerInvariant(KEY_TRUE, address(falseInv), AlwaysFalseInvariant.alwaysFalse.selector);

        (address t, bytes4 sel) = checker.getInvariant(KEY_TRUE);
        assertEq(t, address(falseInv));
        assertEq(sel, AlwaysFalseInvariant.alwaysFalse.selector);
    }

    // -------------------------------------------------------------------------
    // unregisterInvariant — access control
    // -------------------------------------------------------------------------

    function test_UnregisterByNonAdminReverts() public {
        vm.prank(admin);
        checker.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, DEFAULT_ADMIN_ROLE
            )
        );
        checker.unregisterInvariant(KEY_TRUE);
    }

    // -------------------------------------------------------------------------
    // unregisterInvariant — never-registered key
    // -------------------------------------------------------------------------

    function test_UnregisterNeverRegisteredKeyReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantNotRegistered.selector, KEY_UNREGISTERED));
        checker.unregisterInvariant(KEY_UNREGISTERED);
    }

    // -------------------------------------------------------------------------
    // unregisterInvariant — happy path
    // -------------------------------------------------------------------------

    function test_UnregisterRemovesEntry() public {
        vm.prank(admin);
        checker.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        vm.prank(admin);
        checker.unregisterInvariant(KEY_TRUE);

        (address t,) = checker.getInvariant(KEY_TRUE);
        assertEq(t, address(0));
    }

    function test_UnregisterEmitsEvent() public {
        vm.prank(admin);
        checker.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IInvariantChecker.InvariantUnregistered(KEY_TRUE);
        checker.unregisterInvariant(KEY_TRUE);
    }

    function test_CheckAfterUnregisterReverts() public {
        vm.prank(admin);
        checker.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        vm.prank(admin);
        checker.unregisterInvariant(KEY_TRUE);

        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantNotRegistered.selector, KEY_TRUE));
        checker.checkInvariant(KEY_TRUE);
    }

    // -------------------------------------------------------------------------
    // checkInvariant — unregistered
    // -------------------------------------------------------------------------

    function test_CheckUnregisteredReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantNotRegistered.selector, KEY_UNREGISTERED));
        checker.checkInvariant(KEY_UNREGISTERED);
    }

    // -------------------------------------------------------------------------
    // checkInvariant — passing invariant
    // -------------------------------------------------------------------------

    function test_CheckPassingInvariantSucceeds() public {
        vm.prank(admin);
        checker.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        checker.checkInvariant(KEY_TRUE); // must not revert
    }

    // -------------------------------------------------------------------------
    // checkInvariant — failing invariant
    // -------------------------------------------------------------------------

    function test_CheckFailingInvariantReverts() public {
        vm.prank(admin);
        checker.registerInvariant(KEY_FALSE, address(falseInv), AlwaysFalseInvariant.alwaysFalse.selector);

        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantViolatedError.selector, KEY_FALSE));
        checker.checkInvariant(KEY_FALSE);
    }

    // -------------------------------------------------------------------------
    // checkInvariant — reverted staticcall
    // -------------------------------------------------------------------------

    function test_CheckRevertingTargetReverts() public {
        vm.prank(admin);
        checker.registerInvariant(KEY_REVERT, address(revertInv), RevertingInvariant.alwaysReverts.selector);

        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantCheckFailed.selector, KEY_REVERT));
        checker.checkInvariant(KEY_REVERT);
    }

    // -------------------------------------------------------------------------
    // checkInvariants — batch
    // -------------------------------------------------------------------------

    function test_BatchCheckAllPassingSucceeds() public {
        vm.prank(admin);
        checker.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        bytes32[] memory keys = new bytes32[](2);
        keys[0] = KEY_TRUE;
        keys[1] = KEY_TRUE;

        checker.checkInvariants(keys); // must not revert
    }

    function test_BatchCheckFailsOnFirstFalse() public {
        vm.prank(admin);
        checker.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);
        vm.prank(admin);
        checker.registerInvariant(KEY_FALSE, address(falseInv), AlwaysFalseInvariant.alwaysFalse.selector);

        bytes32[] memory keys = new bytes32[](3);
        keys[0] = KEY_TRUE;
        keys[1] = KEY_FALSE; // fails here
        keys[2] = KEY_TRUE;

        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantViolatedError.selector, KEY_FALSE));
        checker.checkInvariants(keys);
    }

    function test_BatchCheckRevertsOnFirstUnregistered() public {
        vm.prank(admin);
        checker.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        bytes32[] memory keys = new bytes32[](2);
        keys[0] = KEY_TRUE;
        keys[1] = KEY_UNREGISTERED;

        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantNotRegistered.selector, KEY_UNREGISTERED));
        checker.checkInvariants(keys);
    }

    // -------------------------------------------------------------------------
    // getInvariant — returns zero for unregistered
    // -------------------------------------------------------------------------

    function test_GetInvariantReturnsZeroForUnregistered() public view {
        (address t, bytes4 sel) = checker.getInvariant(KEY_UNREGISTERED);
        assertEq(t, address(0));
        assertEq(sel, bytes4(0));
    }
}
