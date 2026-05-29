// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlTimed} from "@lattice/access/AccessControlTimed.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccessControlTimedLib} from "@lattice/access/libraries/AccessControlTimedLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IAccessControlTimed} from "@lattice/interfaces/IAccessControlTimed.sol";
import {Test} from "forge-std/Test.sol";

contract MockAccessControlTimedContract is AccessControlTimed {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        AccessControlTimedLib.__AccessControlTimed_init();
        InitializableLib.postInitializer(s);
    }
}

contract AccessControlTimedTester is Test {
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

    MockAccessControlTimedContract internal ac;
    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);

    function setUp() public {
        vm.warp(1_000_000);
        ac = new MockAccessControlTimedContract();
        ac.initialize(admin);
    }

    function test_GrantRoleTimedSetsWindow() public {
        uint48 start = uint48(block.timestamp);
        uint48 expires = start + 3600;
        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, start, expires);

        assertTrue(ac.hasRole(MINTER_ROLE, alice));
        (uint48 gotStart, uint48 gotExpires) = ac.roleExpiration(MINTER_ROLE, alice);
        assertEq(gotStart, start);
        assertEq(gotExpires, expires);
    }

    function test_HasRoleBeforeStartIsFalse() public {
        uint48 start = uint48(block.timestamp + 100);
        uint48 expires = start + 1000;
        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, start, expires);
        assertFalse(ac.hasRole(MINTER_ROLE, alice));
    }

    function test_HasRoleAtStartIsTrue() public {
        uint48 start = uint48(block.timestamp + 100);
        uint48 expires = start + 1000;
        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, start, expires);
        vm.warp(start);
        assertTrue(ac.hasRole(MINTER_ROLE, alice));
    }

    function test_HasRoleAtExpiresIsTrue() public {
        uint48 start = uint48(block.timestamp);
        uint48 expires = start + 1000;
        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, start, expires);
        vm.warp(expires);
        assertTrue(ac.hasRole(MINTER_ROLE, alice));
    }

    function test_HasRoleAfterExpiresIsFalse() public {
        uint48 start = uint48(block.timestamp);
        uint48 expires = start + 1000;
        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, start, expires);
        vm.warp(uint256(expires) + 1);
        assertFalse(ac.hasRole(MINTER_ROLE, alice));
    }

    function test_UntimedGrantIsTimeless() public {
        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, 0, 0);
        vm.warp(block.timestamp + 365 days);
        assertTrue(ac.hasRole(MINTER_ROLE, alice));
    }

    function test_GrantTimedExpiryInPastReverts() public {
        uint48 expires = uint48(block.timestamp - 1);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessControlTimed.AccessControlTimedExpiryInPast.selector, expires));
        ac.grantRoleTimed(MINTER_ROLE, alice, 0, expires);
    }

    function test_GrantTimedExpiryAtNowReverts() public {
        uint48 expires = uint48(block.timestamp);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessControlTimed.AccessControlTimedExpiryInPast.selector, expires));
        ac.grantRoleTimed(MINTER_ROLE, alice, 0, expires);
    }

    function test_GrantTimedInvalidWindowReverts() public {
        uint48 start = uint48(block.timestamp + 1000);
        uint48 expires = uint48(block.timestamp + 500);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControlTimed.AccessControlTimedInvalidWindow.selector, start, expires)
        );
        ac.grantRoleTimed(MINTER_ROLE, alice, start, expires);
    }

    function test_GrantTimedStartEqualsExpiresIsAllowed() public {
        uint48 t = uint48(block.timestamp + 100);
        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, t, t);
        vm.warp(t);
        assertTrue(ac.hasRole(MINTER_ROLE, alice));
        vm.warp(uint256(t) + 1);
        assertFalse(ac.hasRole(MINTER_ROLE, alice));
    }

    function test_GrantTimedByNonAdminReverts() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE)
        );
        ac.grantRoleTimed(MINTER_ROLE, alice, 0, 0);
    }

    function test_ExtendRoleUpdatesExpiry() public {
        uint48 start = uint48(block.timestamp);
        uint48 expires = start + 1000;
        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, start, expires);

        uint48 newExpires = expires + 500;
        vm.prank(admin);
        ac.extendRole(MINTER_ROLE, alice, newExpires);

        (, uint48 got) = ac.roleExpiration(MINTER_ROLE, alice);
        assertEq(got, newExpires);
    }

    function test_ExtendRoleNotExtendedReverts() public {
        uint48 start = uint48(block.timestamp);
        uint48 expires = start + 1000;
        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, start, expires);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControlTimed.AccessControlTimedExpiryNotExtended.selector, expires, expires)
        );
        ac.extendRole(MINTER_ROLE, alice, expires);
    }

    function test_ExtendRoleNotHeldReverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControlTimed.AccessControlTimedRoleNotHeld.selector, MINTER_ROLE, alice)
        );
        ac.extendRole(MINTER_ROLE, alice, uint48(block.timestamp + 1000));
    }

    function test_RevokeClearsTiming() public {
        uint48 start = uint48(block.timestamp);
        uint48 expires = start + 1000;
        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, start, expires);

        vm.prank(admin);
        ac.revokeRole(MINTER_ROLE, alice);

        assertFalse(ac.hasRole(MINTER_ROLE, alice));
        (uint48 gotStart, uint48 gotExpires) = ac.roleExpiration(MINTER_ROLE, alice);
        assertEq(gotStart, 0);
        assertEq(gotExpires, 0);
    }

    function test_BaseGrantRoleIsAliasForUntimed() public {
        vm.prank(admin);
        ac.grantRole(MINTER_ROLE, alice);
        (uint48 start, uint48 expires) = ac.roleExpiration(MINTER_ROLE, alice);
        assertEq(start, uint48(block.timestamp));
        assertEq(expires, 0);
        assertTrue(ac.hasRole(MINTER_ROLE, alice));
    }

    function test_RegrantingResetsWindow() public {
        uint48 firstStart = uint48(block.timestamp);
        uint48 firstExpires = firstStart + 100;
        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, firstStart, firstExpires);

        uint48 secondStart = uint48(block.timestamp + 50);
        uint48 secondExpires = secondStart + 500;
        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, secondStart, secondExpires);

        (uint48 gotStart, uint48 gotExpires) = ac.roleExpiration(MINTER_ROLE, alice);
        assertEq(gotStart, secondStart);
        assertEq(gotExpires, secondExpires);
    }
}
