// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IInvariantChecker} from "@lattice/interfaces/IInvariantChecker.sol";
import {InvariantChecker} from "@lattice/security/InvariantChecker.sol";
import {InvariantCheckerLib} from "@lattice/security/libraries/InvariantCheckerLib.sol";
import {Test} from "forge-std/Test.sol";

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

// -------------------------------------------------------------------------
// Mock contract
// -------------------------------------------------------------------------

/// @title MockInvariantCheckerContract
/// @notice Test double combining InvariantChecker + AccessControl.
contract MockInvariantCheckerContract is InvariantChecker, AccessControl {
    /// @notice Initializes both AccessControl and InvariantChecker modules.
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        InvariantCheckerLib.__InvariantChecker_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// -------------------------------------------------------------------------
// Test contract
// -------------------------------------------------------------------------

/// @title InvariantCheckerTester
/// @notice Comprehensive tests for the InvariantChecker module.
contract InvariantCheckerTester is Test {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 private constant KEY_TRUE = keccak256("KEY_TRUE");
    bytes32 private constant KEY_FALSE = keccak256("KEY_FALSE");
    bytes32 private constant KEY_REVERT = keccak256("KEY_REVERT");
    bytes32 private constant KEY_UNREGISTERED = keccak256("KEY_UNREGISTERED");

    MockInvariantCheckerContract internal mock;
    AlwaysTrueInvariant internal trueInv;
    AlwaysFalseInvariant internal falseInv;
    RevertingInvariant internal revertInv;

    address internal admin = address(0xA1);
    address internal nonAdmin = address(0xB2);

    function setUp() public {
        mock = new MockInvariantCheckerContract();
        mock.initialize(admin);

        trueInv = new AlwaysTrueInvariant();
        falseInv = new AlwaysFalseInvariant();
        revertInv = new RevertingInvariant();
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    function test_ERC165RegisteredIInvariantChecker() public view {
        assertTrue(mock.supportsInterface(type(IInvariantChecker).interfaceId));
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
        mock.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);
    }

    // -------------------------------------------------------------------------
    // registerInvariant — zero target
    // -------------------------------------------------------------------------

    function test_RegisterWithZeroTargetReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantInvalidTarget.selector));
        mock.registerInvariant(KEY_TRUE, address(0), AlwaysTrueInvariant.alwaysTrue.selector);
    }

    // -------------------------------------------------------------------------
    // registerInvariant — happy path
    // -------------------------------------------------------------------------

    function test_RegisterStoresValues() public {
        vm.prank(admin);
        mock.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        (address t, bytes4 sel) = mock.getInvariant(KEY_TRUE);
        assertEq(t, address(trueInv));
        assertEq(sel, AlwaysTrueInvariant.alwaysTrue.selector);
    }

    function test_RegisterEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IInvariantChecker.InvariantRegistered(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);
        mock.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);
    }

    // -------------------------------------------------------------------------
    // registerInvariant — overwrite existing
    // -------------------------------------------------------------------------

    function test_RegisterInvariantOverwritesSilently() public {
        vm.prank(admin);
        mock.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        // Overwrite with a different target — should succeed silently and update the entry.
        vm.prank(admin);
        mock.registerInvariant(KEY_TRUE, address(falseInv), AlwaysFalseInvariant.alwaysFalse.selector);

        (address t, bytes4 sel) = mock.getInvariant(KEY_TRUE);
        assertEq(t, address(falseInv));
        assertEq(sel, AlwaysFalseInvariant.alwaysFalse.selector);
    }

    // -------------------------------------------------------------------------
    // unregisterInvariant — access control
    // -------------------------------------------------------------------------

    function test_UnregisterByNonAdminReverts() public {
        vm.prank(admin);
        mock.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, DEFAULT_ADMIN_ROLE
            )
        );
        mock.unregisterInvariant(KEY_TRUE);
    }

    // -------------------------------------------------------------------------
    // unregisterInvariant — never-registered key
    // -------------------------------------------------------------------------

    function test_UnregisterNeverRegisteredKeyReverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IInvariantChecker.InvariantNotRegistered.selector, KEY_UNREGISTERED)
        );
        mock.unregisterInvariant(KEY_UNREGISTERED);
    }

    // -------------------------------------------------------------------------
    // unregisterInvariant — happy path
    // -------------------------------------------------------------------------

    function test_UnregisterRemovesEntry() public {
        vm.prank(admin);
        mock.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        vm.prank(admin);
        mock.unregisterInvariant(KEY_TRUE);

        (address t,) = mock.getInvariant(KEY_TRUE);
        assertEq(t, address(0));
    }

    function test_UnregisterEmitsEvent() public {
        vm.prank(admin);
        mock.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IInvariantChecker.InvariantUnregistered(KEY_TRUE);
        mock.unregisterInvariant(KEY_TRUE);
    }

    function test_CheckAfterUnregisterReverts() public {
        vm.prank(admin);
        mock.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        vm.prank(admin);
        mock.unregisterInvariant(KEY_TRUE);

        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantNotRegistered.selector, KEY_TRUE));
        mock.checkInvariant(KEY_TRUE);
    }

    // -------------------------------------------------------------------------
    // checkInvariant — unregistered
    // -------------------------------------------------------------------------

    function test_CheckUnregisteredReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantNotRegistered.selector, KEY_UNREGISTERED));
        mock.checkInvariant(KEY_UNREGISTERED);
    }

    // -------------------------------------------------------------------------
    // checkInvariant — passing invariant
    // -------------------------------------------------------------------------

    function test_CheckPassingInvariantSucceeds() public {
        vm.prank(admin);
        mock.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        mock.checkInvariant(KEY_TRUE); // must not revert
    }

    // -------------------------------------------------------------------------
    // checkInvariant — failing invariant
    // -------------------------------------------------------------------------

    function test_CheckFailingInvariantReverts() public {
        vm.prank(admin);
        mock.registerInvariant(KEY_FALSE, address(falseInv), AlwaysFalseInvariant.alwaysFalse.selector);

        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantViolatedError.selector, KEY_FALSE));
        mock.checkInvariant(KEY_FALSE);
    }

    // -------------------------------------------------------------------------
    // checkInvariant — reverted staticcall
    // -------------------------------------------------------------------------

    function test_CheckRevertingTargetReverts() public {
        vm.prank(admin);
        mock.registerInvariant(KEY_REVERT, address(revertInv), RevertingInvariant.alwaysReverts.selector);

        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantCheckFailed.selector, KEY_REVERT));
        mock.checkInvariant(KEY_REVERT);
    }

    // -------------------------------------------------------------------------
    // checkInvariants — batch
    // -------------------------------------------------------------------------

    function test_BatchCheckAllPassingSucceeds() public {
        vm.prank(admin);
        mock.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        bytes32[] memory keys = new bytes32[](2);
        keys[0] = KEY_TRUE;
        keys[1] = KEY_TRUE;

        mock.checkInvariants(keys); // must not revert
    }

    function test_BatchCheckFailsOnFirstFalse() public {
        vm.prank(admin);
        mock.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);
        vm.prank(admin);
        mock.registerInvariant(KEY_FALSE, address(falseInv), AlwaysFalseInvariant.alwaysFalse.selector);

        bytes32[] memory keys = new bytes32[](3);
        keys[0] = KEY_TRUE;
        keys[1] = KEY_FALSE; // fails here
        keys[2] = KEY_TRUE;

        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantViolatedError.selector, KEY_FALSE));
        mock.checkInvariants(keys);
    }

    function test_BatchCheckRevertsOnFirstUnregistered() public {
        vm.prank(admin);
        mock.registerInvariant(KEY_TRUE, address(trueInv), AlwaysTrueInvariant.alwaysTrue.selector);

        bytes32[] memory keys = new bytes32[](2);
        keys[0] = KEY_TRUE;
        keys[1] = KEY_UNREGISTERED;

        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantNotRegistered.selector, KEY_UNREGISTERED));
        mock.checkInvariants(keys);
    }

    // -------------------------------------------------------------------------
    // getInvariant — returns zero for unregistered
    // -------------------------------------------------------------------------

    function test_GetInvariantReturnsZeroForUnregistered() public view {
        (address t, bytes4 sel) = mock.getInvariant(KEY_UNREGISTERED);
        assertEq(t, address(0));
        assertEq(sel, bytes4(0));
    }
}
