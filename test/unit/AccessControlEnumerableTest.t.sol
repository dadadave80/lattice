// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlEnumerableTestBase} from "@lattice-test/base/AccessControlEnumerableTestBase.sol";
import {AccessControlEnumerable} from "@lattice/access/AccessControlEnumerable.sol";

/// @title AccessControlEnumerableTest
/// @notice Exercises the AccessControlEnumerable facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployAccessControlEnumerable} script (see {AccessControlEnumerableTestBase}) — the enumerable flavor
///         is cut in place of the base `AccessControl` facet, so every role + enumeration call routes through the
///         diamond's `delegatecall` dispatch, not a flattened inheritance mock.
contract AccessControlEnumerableTest is AccessControlEnumerableTestBase {
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA101);

    function setUp() public {
        diamond = _deployAccessControlEnumerable(admin);
        ac = AccessControlEnumerable(diamond);
    }

    function test_GrantRoleAddsMember() public {
        vm.prank(admin);
        ac.grantRole(MINTER_ROLE, alice);
        assertEq(ac.getRoleMemberCount(MINTER_ROLE), 1);
        assertEq(ac.getRoleMember(MINTER_ROLE, 0), alice);
    }

    function test_MultipleMembersOrderedByGrantOrder() public {
        vm.startPrank(admin);
        ac.grantRole(MINTER_ROLE, alice);
        ac.grantRole(MINTER_ROLE, bob);
        ac.grantRole(MINTER_ROLE, carol);
        vm.stopPrank();

        assertEq(ac.getRoleMemberCount(MINTER_ROLE), 3);
        assertEq(ac.getRoleMember(MINTER_ROLE, 0), alice);
        assertEq(ac.getRoleMember(MINTER_ROLE, 1), bob);
        assertEq(ac.getRoleMember(MINTER_ROLE, 2), carol);
    }

    function test_GetRoleMembersReturnsAll() public {
        vm.startPrank(admin);
        ac.grantRole(MINTER_ROLE, alice);
        ac.grantRole(MINTER_ROLE, bob);
        vm.stopPrank();

        address[] memory members = ac.getRoleMembers(MINTER_ROLE);
        assertEq(members.length, 2);
        assertEq(members[0], alice);
        assertEq(members[1], bob);
    }

    function test_GetRoleMembersOnEmptyRoleReturnsEmpty() public view {
        address[] memory members = ac.getRoleMembers(MINTER_ROLE);
        assertEq(members.length, 0);
    }

    function test_RevokeRoleRemovesMember() public {
        vm.startPrank(admin);
        ac.grantRole(MINTER_ROLE, alice);
        ac.grantRole(MINTER_ROLE, bob);
        ac.grantRole(MINTER_ROLE, carol);
        ac.revokeRole(MINTER_ROLE, bob);
        vm.stopPrank();

        assertEq(ac.getRoleMemberCount(MINTER_ROLE), 2);
        assertEq(ac.getRoleMember(MINTER_ROLE, 0), alice);
        assertEq(ac.getRoleMember(MINTER_ROLE, 1), carol);
        assertFalse(ac.hasRole(MINTER_ROLE, bob));
    }

    function test_GrantSameMemberTwiceDoesNotDuplicate() public {
        vm.startPrank(admin);
        ac.grantRole(MINTER_ROLE, alice);
        ac.grantRole(MINTER_ROLE, alice);
        vm.stopPrank();
        assertEq(ac.getRoleMemberCount(MINTER_ROLE), 1);
    }

    function test_GetRoleMemberOutOfBoundsReverts() public {
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x32));
        ac.getRoleMember(MINTER_ROLE, 0);
    }

    function test_RenounceRoleRemovesMember() public {
        vm.prank(admin);
        ac.grantRole(MINTER_ROLE, alice);

        vm.prank(alice);
        ac.renounceRole(MINTER_ROLE, alice);

        assertEq(ac.getRoleMemberCount(MINTER_ROLE), 0);
        assertFalse(ac.hasRole(MINTER_ROLE, alice));
    }
}
