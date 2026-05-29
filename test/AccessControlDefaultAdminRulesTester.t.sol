// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {AccessControlDefaultAdminRules} from "@lattice/access/AccessControlDefaultAdminRules.sol";
import {AccessControlDefaultAdminRulesLib} from "@lattice/access/libraries/AccessControlDefaultAdminRulesLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IAccessControlDefaultAdminRules} from "@lattice/interfaces/IAccessControlDefaultAdminRules.sol";
import {TimelockLib} from "@lattice/utils/libraries/TimelockLib.sol";
import {Test} from "forge-std/Test.sol";

contract MockDefaultAdminRulesContract is AccessControlDefaultAdminRules {
    function initialize(address _admin, uint48 _delay) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        OwnableLib.initializeOwner(_admin);
        AccessControlLib.__AccessControl_init(_admin);
        AccessControlDefaultAdminRulesLib.__AccessControlDefaultAdminRules_init(_delay);
        InitializableLib.postInitializer(s);
    }
}

contract AccessControlDefaultAdminRulesTester is Test {
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint48 constant INITIAL_DELAY = 1 days;

    MockDefaultAdminRulesContract internal ac;
    address internal admin = address(0xA1);
    address internal newAdmin = address(0xA2);
    address internal alice = address(0xA11CE);

    function setUp() public {
        vm.warp(1_000_000);
        ac = new MockDefaultAdminRulesContract();
        ac.initialize(admin, INITIAL_DELAY);
    }

    function test_DefaultAdminIsOwner() public view {
        assertEq(ac.defaultAdmin(), admin);
        assertTrue(ac.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertFalse(ac.hasRole(DEFAULT_ADMIN_ROLE, newAdmin));
    }

    function test_DefaultAdminDelayInitiallySet() public view {
        assertEq(ac.defaultAdminDelay(), INITIAL_DELAY);
    }

    function test_GrantDefaultAdminRoleReverts() public {
        vm.prank(admin);
        vm.expectRevert(IAccessControlDefaultAdminRules.AccessControlDefaultAdminRulesUseAdminTransfer.selector);
        ac.grantRole(DEFAULT_ADMIN_ROLE, alice);
    }

    function test_RevokeDefaultAdminRoleReverts() public {
        vm.prank(admin);
        vm.expectRevert(IAccessControlDefaultAdminRules.AccessControlDefaultAdminRulesUseAdminTransfer.selector);
        ac.revokeRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function test_RenounceDefaultAdminRoleReverts() public {
        vm.prank(admin);
        vm.expectRevert(IAccessControlDefaultAdminRules.AccessControlDefaultAdminRulesUseAdminTransfer.selector);
        ac.renounceRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function test_GrantOtherRoleStillWorks() public {
        vm.prank(admin);
        ac.grantRole(MINTER_ROLE, alice);
        assertTrue(ac.hasRole(MINTER_ROLE, alice));
    }

    function test_BeginAdminTransferScheduleStored() public {
        vm.prank(admin);
        ac.beginDefaultAdminTransfer(newAdmin);

        (address pending, uint48 readyAt) = ac.pendingDefaultAdmin();
        assertEq(pending, newAdmin);
        assertEq(readyAt, uint48(block.timestamp + INITIAL_DELAY));
    }

    function test_BeginAdminTransferByNonOwnerReverts() public {
        vm.prank(alice);
        vm.expectRevert(OwnableLib.Unauthorized.selector);
        ac.beginDefaultAdminTransfer(newAdmin);
    }

    function test_AcceptBeforeReadyReverts() public {
        vm.prank(admin);
        ac.beginDefaultAdminTransfer(newAdmin);

        vm.prank(newAdmin);
        uint48 expectedReady = uint48(block.timestamp + INITIAL_DELAY);
        vm.expectRevert(
            abi.encodeWithSelector(TimelockLib.TimelockNotReady.selector, expectedReady, uint48(block.timestamp))
        );
        ac.acceptDefaultAdminTransfer();
    }

    function test_AcceptByWrongAddressReverts() public {
        vm.prank(admin);
        ac.beginDefaultAdminTransfer(newAdmin);

        vm.warp(block.timestamp + INITIAL_DELAY);
        vm.prank(alice);
        vm.expectRevert(IAccessControlDefaultAdminRules.AccessControlDefaultAdminRulesUnauthorizedAccept.selector);
        ac.acceptDefaultAdminTransfer();
    }

    function test_AcceptTransfersOwnership() public {
        vm.prank(admin);
        ac.beginDefaultAdminTransfer(newAdmin);

        vm.warp(block.timestamp + INITIAL_DELAY);
        vm.prank(newAdmin);
        ac.acceptDefaultAdminTransfer();

        assertEq(ac.defaultAdmin(), newAdmin);
        assertTrue(ac.hasRole(DEFAULT_ADMIN_ROLE, newAdmin));
        assertFalse(ac.hasRole(DEFAULT_ADMIN_ROLE, admin));

        (address pending, uint48 readyAt) = ac.pendingDefaultAdmin();
        assertEq(pending, address(0));
        assertEq(readyAt, 0);
    }

    function test_CancelClearsPending() public {
        vm.prank(admin);
        ac.beginDefaultAdminTransfer(newAdmin);

        vm.prank(admin);
        ac.cancelDefaultAdminTransfer();

        (address pending, uint48 readyAt) = ac.pendingDefaultAdmin();
        assertEq(pending, address(0));
        assertEq(readyAt, 0);
    }

    function test_CancelByNonOwnerReverts() public {
        vm.prank(admin);
        ac.beginDefaultAdminTransfer(newAdmin);

        vm.prank(alice);
        vm.expectRevert(OwnableLib.Unauthorized.selector);
        ac.cancelDefaultAdminTransfer();
    }

    function test_BeginOverwritesExistingPending() public {
        address otherAdmin = address(0xA3);
        vm.prank(admin);
        ac.beginDefaultAdminTransfer(newAdmin);

        vm.prank(admin);
        ac.beginDefaultAdminTransfer(otherAdmin);

        (address pending,) = ac.pendingDefaultAdmin();
        assertEq(pending, otherAdmin);
    }

    function test_ChangeDelayDecreaseAppliesImmediately() public {
        uint48 newDelay = INITIAL_DELAY - 100;
        vm.prank(admin);
        ac.changeDefaultAdminDelay(newDelay);

        // wait == 0 because newDelay < currentDelay; pending is "ready" at block.timestamp.
        assertEq(ac.defaultAdminDelay(), newDelay);
    }

    function test_ChangeDelayIncreaseRequiresWait() public {
        uint48 newDelay = INITIAL_DELAY + 100;
        vm.prank(admin);
        ac.changeDefaultAdminDelay(newDelay);

        // Effective delay still old until DELAY_INCREASE_WAIT elapses.
        assertEq(ac.defaultAdminDelay(), INITIAL_DELAY);

        vm.warp(block.timestamp + 5 days);
        assertEq(ac.defaultAdminDelay(), newDelay);
    }

    function test_PendingDelayReports() public {
        uint48 newDelay = INITIAL_DELAY + 100;
        vm.prank(admin);
        ac.changeDefaultAdminDelay(newDelay);

        (uint48 pending, uint48 readyAt) = ac.pendingDefaultAdminDelay();
        assertEq(pending, newDelay);
        assertEq(readyAt, uint48(block.timestamp + 5 days));
    }

    function test_RollbackClearsPendingDelay() public {
        vm.prank(admin);
        ac.changeDefaultAdminDelay(INITIAL_DELAY + 100);

        vm.prank(admin);
        ac.rollbackDefaultAdminDelay();

        (uint48 pending, uint48 readyAt) = ac.pendingDefaultAdminDelay();
        assertEq(pending, 0);
        assertEq(readyAt, 0);
    }

    function test_DefaultAdminDelayIncreaseWaitIsFiveDays() public view {
        assertEq(ac.defaultAdminDelayIncreaseWait(), uint48(5 days));
    }
}
