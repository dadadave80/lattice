// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IEmergencyStop} from "@lattice/interfaces/security/IEmergencyStop.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {EMERGENCY_GUARDIAN_ROLE, EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {Test, Vm} from "forge-std/Test.sol";

/// @title MockEmergencyStopContract
/// @notice Test double combining EmergencyStop + AccessControl.
contract MockEmergencyStopContract is EmergencyStop, AccessControl {
    /// @notice Initializes both AccessControl and EmergencyStop modules.
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        EmergencyStopLib.__EmergencyStop_init();
        InitializableLib.postInitializer(s);
    }

    /// @notice External gate that reverts when the emergency stop is active.
    function gatedAction() external view {
        EmergencyStopLib.checkNotStopped();
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title EmergencyStopTest
/// @notice Comprehensive tests for the EmergencyStop module.
contract EmergencyStopTest is Test {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;

    MockEmergencyStopContract internal mock;
    address internal admin = address(0xA1);
    address internal guardian = address(0xB2);
    address internal nonGuardian = address(0xC3);

    function setUp() public {
        mock = new MockEmergencyStopContract();
        mock.initialize(admin);

        // Grant guardian role to the guardian address.
        vm.prank(admin);
        mock.addGuardian(guardian);
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    function test_ERC165RegisteredIEmergencyStop() public view {
        assertTrue(mock.supportsInterface(type(IEmergencyStop).interfaceId));
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    function test_InitiallyNotStopped() public view {
        assertFalse(mock.isStopped());
    }

    function test_InitialReasonIsEmpty() public view {
        assertEq(mock.stoppedReason(), "");
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
        mock.addGuardian(nonGuardian);
    }

    function test_AddGuardianGrantsRole() public view {
        assertTrue(mock.isGuardian(guardian));
    }

    function test_AddGuardianEmitsEvent() public {
        address newGuardian = address(0xD4);
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IEmergencyStop.GuardianAdded(newGuardian);
        mock.addGuardian(newGuardian);
    }

    function test_AddGuardianTwiceEmitsOnlyOnce() public {
        address newGuardian = address(0xD4);
        vm.prank(admin);
        mock.addGuardian(newGuardian);

        // Second call on the same address — must NOT emit GuardianAdded.
        vm.prank(admin);
        vm.recordLogs();
        mock.addGuardian(newGuardian);
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
        mock.removeGuardian(notAGuardian);
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
        mock.removeGuardian(guardian);
    }

    function test_RemoveGuardianRevokesRole() public {
        vm.prank(admin);
        mock.removeGuardian(guardian);
        assertFalse(mock.isGuardian(guardian));
    }

    function test_RemoveGuardianEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IEmergencyStop.GuardianRemoved(guardian);
        mock.removeGuardian(guardian);
    }

    // -------------------------------------------------------------------------
    // emergencyStop — access control
    // -------------------------------------------------------------------------

    function test_EmergencyStopByNonGuardianReverts() public {
        vm.prank(nonGuardian);
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopUnauthorizedGuardian.selector, nonGuardian));
        mock.emergencyStop("hack detected");
    }

    function test_AdminWithoutGuardianRoleCannotStop() public {
        // The admin has DEFAULT_ADMIN_ROLE but NOT EMERGENCY_GUARDIAN_ROLE by default.
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopUnauthorizedGuardian.selector, admin));
        mock.emergencyStop("testing");
    }

    // -------------------------------------------------------------------------
    // emergencyStop — happy path
    // -------------------------------------------------------------------------

    function test_GuardianCanStop() public {
        vm.prank(guardian);
        mock.emergencyStop("vulnerability found");

        assertTrue(mock.isStopped());
    }

    function test_EmergencyStopSetsReason() public {
        vm.prank(guardian);
        mock.emergencyStop("critical bug");

        assertEq(mock.stoppedReason(), "critical bug");
    }

    function test_EmergencyStopEmitsEvent() public {
        vm.prank(guardian);
        vm.expectEmit(true, true, true, true);
        emit IEmergencyStop.EmergencyStopped(guardian, "reason");
        mock.emergencyStop("reason");
    }

    // -------------------------------------------------------------------------
    // emergencyStop — double stop
    // -------------------------------------------------------------------------

    function test_DoubleStopReverts() public {
        vm.prank(guardian);
        mock.emergencyStop("first stop");

        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        mock.emergencyStop("second stop");
    }

    // -------------------------------------------------------------------------
    // checkNotStopped
    // -------------------------------------------------------------------------

    function test_CheckNotStoppedSucceedsWhenNotStopped() public view {
        mock.gatedAction(); // must not revert
    }

    function test_CheckNotStoppedRevertsWhenStopped() public {
        vm.prank(guardian);
        mock.emergencyStop("stop now");

        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        mock.gatedAction();
    }

    // -------------------------------------------------------------------------
    // emergencyResume — access control
    // -------------------------------------------------------------------------

    function test_EmergencyResumeByGuardianReverts() public {
        vm.prank(guardian);
        mock.emergencyStop("stop");

        // Guardian cannot resume — only admin can.
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, guardian, DEFAULT_ADMIN_ROLE
            )
        );
        mock.emergencyResume();
    }

    function test_EmergencyResumeByNonAdminReverts() public {
        vm.prank(guardian);
        mock.emergencyStop("stop");

        vm.prank(nonGuardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonGuardian, DEFAULT_ADMIN_ROLE
            )
        );
        mock.emergencyResume();
    }

    // -------------------------------------------------------------------------
    // emergencyResume — not stopped
    // -------------------------------------------------------------------------

    function test_ResumeWhenNotStoppedReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopNotActive.selector));
        mock.emergencyResume();
    }

    // -------------------------------------------------------------------------
    // emergencyResume — happy path
    // -------------------------------------------------------------------------

    function test_AdminCanResume() public {
        vm.prank(guardian);
        mock.emergencyStop("stop");

        vm.prank(admin);
        mock.emergencyResume();

        assertFalse(mock.isStopped());
    }

    function test_ResumeEmitsEvent() public {
        vm.prank(guardian);
        mock.emergencyStop("stop");

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IEmergencyStop.EmergencyResumed(admin);
        mock.emergencyResume();
    }

    function test_ResumeAfterResumePreventsDoubleResume() public {
        vm.prank(guardian);
        mock.emergencyStop("stop");

        vm.prank(admin);
        mock.emergencyResume();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopNotActive.selector));
        mock.emergencyResume();
    }

    // -------------------------------------------------------------------------
    // stop / resume cycle
    // -------------------------------------------------------------------------

    function test_StopResumeCycle() public {
        vm.prank(guardian);
        mock.emergencyStop("round 1");
        assertTrue(mock.isStopped());

        vm.prank(admin);
        mock.emergencyResume();
        assertFalse(mock.isStopped());

        vm.prank(guardian);
        mock.emergencyStop("round 2");
        assertTrue(mock.isStopped());
        assertEq(mock.stoppedReason(), "round 2");
    }

    // -------------------------------------------------------------------------
    // guard function after resume
    // -------------------------------------------------------------------------

    function test_GatedActionSucceedsAfterResume() public {
        vm.prank(guardian);
        mock.emergencyStop("stop");

        vm.prank(admin);
        mock.emergencyResume();

        mock.gatedAction(); // must not revert
    }
}
