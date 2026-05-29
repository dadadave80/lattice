// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlEnumerable} from "@lattice/access/AccessControlEnumerable.sol";
import {AccessControlEnumerableLib} from "@lattice/access/libraries/AccessControlEnumerableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";

contract MockAccessControlEnumerableContract is AccessControlEnumerable {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        AccessControlEnumerableLib.__AccessControlEnumerable_init();
        InitializableLib.postInitializer(s);
    }
}

contract AccessControlEnumerableTester is Test {
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

    MockAccessControlEnumerableContract internal ac;
    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA101);

    function setUp() public {
        ac = new MockAccessControlEnumerableContract();
        ac.initialize(admin);
    }

    function test_GrantRoleAddsMember() public {
        vm.prank(admin);
        ac.grantRole(MINTER_ROLE, alice);
        assertEq(ac.getRoleMemberCount(MINTER_ROLE), 1);
        assertEq(ac.getRoleMember(MINTER_ROLE, 0), alice);
    }
}
