// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlTimedTestBase} from "@lattice-test/base/AccessControlTimedTestBase.sol";
import {AccessControlTimed} from "@lattice/access/AccessControlTimed.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IAccessControlTimed} from "@lattice/interfaces/access/IAccessControlTimed.sol";

/// @title AccessControlTimedTest
/// @notice Exercises the AccessControlTimed facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployAccessControlTimed} script (see {AccessControlTimedTestBase}) — the timed flavor is cut in
///         place of the base `AccessControl` facet, so every role + timed-window call routes through the
///         diamond's `delegatecall` dispatch, not a flattened inheritance mock.
contract AccessControlTimedTest is AccessControlTimedTestBase {
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);

    function setUp() public {
        vm.warp(1_000_000);
        diamond = _deployAccessControlTimed(admin);
        ac = AccessControlTimed(diamond);
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

    /// @notice T-2 / M-1 regression: extendRole on a timeless grant must revert.
    function test_ExtendRoleOnTimelessGrantReverts() public {
        // Plain grantRole gives a timeless grant (expires == 0)
        vm.prank(admin);
        ac.grantRole(MINTER_ROLE, alice);
        (, uint48 expires) = ac.roleExpiration(MINTER_ROLE, alice);
        assertEq(expires, 0, "should be timeless");

        // extendRole should revert with AccessControlTimedRoleIsTimeless
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControlTimed.AccessControlTimedRoleIsTimeless.selector, MINTER_ROLE, alice)
        );
        ac.extendRole(MINTER_ROLE, alice, uint48(block.timestamp + 1000));
    }

    /// @notice T-2 / M-1: extendRole on an expired (but not revoked) grant must revert
    ///         because the time-aware hasRole returns false.
    function test_ExtendExpiredGrantReverts() public {
        uint48 start = uint48(block.timestamp);
        uint48 expires = start + 100;
        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, start, expires);

        // Warp past expiry
        vm.warp(uint256(expires) + 1);
        assertFalse(ac.hasRole(MINTER_ROLE, alice));

        // extendRole should see alice as not holding the role
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControlTimed.AccessControlTimedRoleNotHeld.selector, MINTER_ROLE, alice)
        );
        ac.extendRole(MINTER_ROLE, alice, expires + 1000);
    }

    function testFuzz_WindowEnforcement(uint40 startDelta, uint40 windowLen, uint40 probeDelta) public {
        vm.assume(windowLen > 0);
        vm.assume(uint256(startDelta) + uint256(windowLen) < type(uint40).max);

        uint48 start = uint48(block.timestamp + startDelta);
        uint48 expires = start + uint48(windowLen);

        vm.prank(admin);
        ac.grantRoleTimed(MINTER_ROLE, alice, start, expires);

        uint256 probe = block.timestamp + probeDelta;
        vm.warp(probe);
        bool expected = probe >= start && probe <= expires;
        assertEq(ac.hasRole(MINTER_ROLE, alice), expected);
    }
}
