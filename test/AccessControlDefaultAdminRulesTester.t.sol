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
}
