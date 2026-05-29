// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessManagerStandalone} from "@lattice/access/AccessManagerStandalone.sol";
import {Test} from "forge-std/Test.sol";

contract AccessManagerStandaloneTest is Test {
    function test_DeploysAndAdminIsSet() public {
        address admin = address(0xA1);
        AccessManagerStandalone mgr = new AccessManagerStandalone(admin);
        (bool isMember,) = mgr.hasRole(0, admin);
        assertTrue(isMember);
    }
}
