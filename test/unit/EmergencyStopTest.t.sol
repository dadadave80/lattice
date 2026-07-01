// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {EmergencyStopTestBase} from "@lattice-test/base/EmergencyStopTestBase.sol";
import {EmergencyStopTestFacet} from "@lattice-test/helpers/EmergencyStopTestFacet.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IEmergencyStop} from "@lattice/interfaces/security/IEmergencyStop.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title EmergencyStopTest
/// @notice Exercises the EmergencyStop facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployEmergencyStop} script (see {EmergencyStopTestBase}) — every call below routes through the
///         diamond's `delegatecall` dispatch, not a flattened inheritance mock. Admin/guardian gating is enforced
///         by the cut-in `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`; the
///         `checkNotStopped` consumer guard by the appended test-only {EmergencyStopTestFacet}.
contract EmergencyStopTest is EmergencyStopTestBase {
    address internal admin = address(0xA1);
    address internal guardian = address(0xB2);
    address internal nonGuardian = address(0xC3);

    function setUp() public {
        diamond = _deployEmergencyStop(admin);
        emergency = EmergencyStop(diamond);
        guard = EmergencyStopTestFacet(diamond);

        // Grant guardian role to the guardian address.
        vm.prank(admin);
        emergency.addGuardian(guardian);
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    function test_ERC165RegisteredIEmergencyStop() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IEmergencyStop).interfaceId));
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    function test_InitiallyNotStopped() public view {
        assertFalse(emergency.isStopped());
    }

    function test_InitialReasonIsEmpty() public view {
        assertEq(emergency.stoppedReason(), "");
    }

    // -------------------------------------------------------------------------
    // addGuardian
    // -------------------------------------------------------------------------

    function test_AddGuardianByNonAdminReverts() public {
        vm.prank(nonGuardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonGuardian, DEFAULT_ADMIN_ROLE
            )
        );
        emergency.addGuardian(nonGuardian);
    }

    function test_AddGuardianGrantsRole() public view {
        assertTrue(emergency.isGuardian(guardian));
    }

    function test_AddGuardianEmitsEvent() public {
        address newGuardian = address(0xD4);
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IEmergencyStop.GuardianAdded(newGuardian);
        emergency.addGuardian(newGuardian);
    }

    function test_AddGuardianTwiceEmitsOnlyOnce() public {
        address newGuardian = address(0xD4);
        vm.prank(admin);
        emergency.addGuardian(newGuardian);

        // Second call on the same address — must NOT emit GuardianAdded.
        vm.prank(admin);
        vm.recordLogs();
        emergency.addGuardian(newGuardian);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool eventFound = false;
        bytes32 guardianAddedTopic = keccak256("GuardianAdded(address)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == guardianAddedTopic) {
                eventFound = true;
                break;
            }
        }
        assertFalse(eventFound, "GuardianAdded must not emit on no-op addGuardian");
    }

    function test_RemoveNonGuardianEmitsNoEvent() public {
        address notAGuardian = address(0xE5);
        // notAGuardian was never granted the guardian role.
        vm.prank(admin);
        vm.recordLogs();
        emergency.removeGuardian(notAGuardian);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool eventFound = false;
        bytes32 guardianRemovedTopic = keccak256("GuardianRemoved(address)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == guardianRemovedTopic) {
                eventFound = true;
                break;
            }
        }
        assertFalse(eventFound, "GuardianRemoved must not emit when address was not a guardian");
    }

    // -------------------------------------------------------------------------
    // removeGuardian
    // -------------------------------------------------------------------------

    function test_RemoveGuardianByNonAdminReverts() public {
        vm.prank(nonGuardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonGuardian, DEFAULT_ADMIN_ROLE
            )
        );
        emergency.removeGuardian(guardian);
    }

    function test_RemoveGuardianRevokesRole() public {
        vm.prank(admin);
        emergency.removeGuardian(guardian);
        assertFalse(emergency.isGuardian(guardian));
    }

    function test_RemoveGuardianEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IEmergencyStop.GuardianRemoved(guardian);
        emergency.removeGuardian(guardian);
    }

    // -------------------------------------------------------------------------
    // emergencyStop — access control
    // -------------------------------------------------------------------------

    function test_EmergencyStopByNonGuardianReverts() public {
        vm.prank(nonGuardian);
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopUnauthorizedGuardian.selector, nonGuardian));
        emergency.emergencyStop("hack detected");
    }

    function test_AdminWithoutGuardianRoleCannotStop() public {
        // The admin has DEFAULT_ADMIN_ROLE but NOT EMERGENCY_GUARDIAN_ROLE by default.
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopUnauthorizedGuardian.selector, admin));
        emergency.emergencyStop("testing");
    }

    // -------------------------------------------------------------------------
    // emergencyStop — happy path
    // -------------------------------------------------------------------------

    function test_GuardianCanStop() public {
        vm.prank(guardian);
        emergency.emergencyStop("vulnerability found");

        assertTrue(emergency.isStopped());
    }

    function test_EmergencyStopSetsReason() public {
        vm.prank(guardian);
        emergency.emergencyStop("critical bug");

        assertEq(emergency.stoppedReason(), "critical bug");
    }

    function test_EmergencyStopEmitsEvent() public {
        vm.prank(guardian);
        vm.expectEmit(true, true, true, true);
        emit IEmergencyStop.EmergencyStopped(guardian, "reason");
        emergency.emergencyStop("reason");
    }

    // -------------------------------------------------------------------------
    // emergencyStop — double stop
    // -------------------------------------------------------------------------

    function test_DoubleStopReverts() public {
        vm.prank(guardian);
        emergency.emergencyStop("first stop");

        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        emergency.emergencyStop("second stop");
    }

    // -------------------------------------------------------------------------
    // checkNotStopped
    // -------------------------------------------------------------------------

    function test_CheckNotStoppedSucceedsWhenNotStopped() public view {
        guard.gatedAction(); // must not revert
    }

    function test_CheckNotStoppedRevertsWhenStopped() public {
        vm.prank(guardian);
        emergency.emergencyStop("stop now");

        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        guard.gatedAction();
    }

    // -------------------------------------------------------------------------
    // emergencyResume — access control
    // -------------------------------------------------------------------------

    function test_EmergencyResumeByGuardianReverts() public {
        vm.prank(guardian);
        emergency.emergencyStop("stop");

        // Guardian cannot resume — only admin can.
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, guardian, DEFAULT_ADMIN_ROLE
            )
        );
        emergency.emergencyResume();
    }

    function test_EmergencyResumeByNonAdminReverts() public {
        vm.prank(guardian);
        emergency.emergencyStop("stop");

        vm.prank(nonGuardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonGuardian, DEFAULT_ADMIN_ROLE
            )
        );
        emergency.emergencyResume();
    }

    // -------------------------------------------------------------------------
    // emergencyResume — not stopped
    // -------------------------------------------------------------------------

    function test_ResumeWhenNotStoppedReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopNotActive.selector));
        emergency.emergencyResume();
    }

    // -------------------------------------------------------------------------
    // emergencyResume — happy path
    // -------------------------------------------------------------------------

    function test_AdminCanResume() public {
        vm.prank(guardian);
        emergency.emergencyStop("stop");

        vm.prank(admin);
        emergency.emergencyResume();

        assertFalse(emergency.isStopped());
    }

    function test_ResumeEmitsEvent() public {
        vm.prank(guardian);
        emergency.emergencyStop("stop");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IEmergencyStop.EmergencyResumed(admin);
        emergency.emergencyResume();
    }

    function test_ResumeAfterResumePreventsDoubleResume() public {
        vm.prank(guardian);
        emergency.emergencyStop("stop");

        vm.prank(admin);
        emergency.emergencyResume();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopNotActive.selector));
        emergency.emergencyResume();
    }

    // -------------------------------------------------------------------------
    // stop / resume cycle
    // -------------------------------------------------------------------------

    function test_StopResumeCycle() public {
        vm.prank(guardian);
        emergency.emergencyStop("round 1");
        assertTrue(emergency.isStopped());

        vm.prank(admin);
        emergency.emergencyResume();
        assertFalse(emergency.isStopped());

        vm.prank(guardian);
        emergency.emergencyStop("round 2");
        assertTrue(emergency.isStopped());
        assertEq(emergency.stoppedReason(), "round 2");
    }

    // -------------------------------------------------------------------------
    // guard function after resume
    // -------------------------------------------------------------------------

    function test_GatedActionSucceedsAfterResume() public {
        vm.prank(guardian);
        emergency.emergencyStop("stop");

        vm.prank(admin);
        emergency.emergencyResume();

        guard.gatedAction(); // must not revert
    }
}
