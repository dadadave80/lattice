// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessManaged} from "@lattice/access/AccessManaged.sol";
import {AccessManagerStandalone} from "@lattice/access/AccessManagerStandalone.sol";
import {AccessManagedLib} from "@lattice/access/libraries/AccessManagedLib.sol";
import {IAccessManaged} from "@lattice/interfaces/IAccessManaged.sol";
import {Test} from "forge-std/Test.sol";

contract MockAccessManagedContract is AccessManaged {
    function initialize(address _authority) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessManagedLib.__AccessManaged_init(_authority);
        InitializableLib.postInitializer(s);
    }

    function restrictedFn() external view {
        AccessManagedLib.restrictedCheck();
    }
}

contract AccessManagedTester is Test {
    AccessManagerStandalone internal mgr;
    MockAccessManagedContract internal managed;
    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);

    function setUp() public {
        mgr = new AccessManagerStandalone(admin);
        managed = new MockAccessManagedContract();
        managed.initialize(address(mgr));
    }

    function test_AuthorityIsSet() public view {
        assertEq(managed.authority(), address(mgr));
    }

    function test_InitWithZeroAuthorityReverts() public {
        MockAccessManagedContract m2 = new MockAccessManagedContract();
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedInvalidAuthority.selector, address(0)));
        m2.initialize(address(0));
    }

    function test_SetAuthorityByNonAuthorityReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        managed.setAuthority(address(0x123));
    }

    function test_SetAuthorityByAuthorityWorks() public {
        AccessManagerStandalone newMgr = new AccessManagerStandalone(admin);
        vm.prank(address(mgr));
        managed.setAuthority(address(newMgr));
        assertEq(managed.authority(), address(newMgr));
    }

    function test_SetAuthorityEOAReverts() public {
        address eoa = address(0xDEAD);
        vm.prank(address(mgr));
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedInvalidAuthority.selector, eoa));
        managed.setAuthority(eoa);
    }

    function test_InitWithEOAAuthorityReverts() public {
        address eoa = address(0xBEEF);
        MockAccessManagedContract m2 = new MockAccessManagedContract();
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedInvalidAuthority.selector, eoa));
        m2.initialize(eoa);
    }

    function test_RestrictedFnUnauthorizedReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        managed.restrictedFn();
    }

    function test_RestrictedFnAuthorizedPasses() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = managed.restrictedFn.selector;
        vm.prank(admin);
        mgr.setTargetFunctionRole(address(managed), selectors, type(uint64).max);

        vm.prank(alice);
        managed.restrictedFn();
    }
}
