// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessManaged} from "@lattice/access/AccessManaged.sol";
import {AccessManagerStandalone} from "@lattice/access/AccessManagerStandalone.sol";
import {AccessManagedLib} from "@lattice/access/libraries/AccessManagedLib.sol";
import {IAccessManaged} from "@lattice/interfaces/IAccessManaged.sol";
import {IAccessManager} from "@lattice/interfaces/IAccessManager.sol";
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
    uint64 constant CALLER_ROLE = 1;

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

    /// @notice T-1 / H-1 regression: a caller with an execution delay gets
    ///         AccessManagedRequiredDelay when calling directly (without schedule+execute).
    function test_RestrictedFnWithDelayRevertsDirectly() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = managed.restrictedFn.selector;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(managed), selectors, CALLER_ROLE);
        vm.prank(admin);
        mgr.grantRole(CALLER_ROLE, alice, uint32(1 days)); // execution delay

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManaged.AccessManagedRequiredDelay.selector, alice, uint32(1 days))
        );
        managed.restrictedFn();
    }

    /// @notice T-1 / H-1 regression: a caller with an execution delay can succeed through
    ///         AccessManager.execute() after the delay matures. Verifies the _consumingScheduledOp
    ///         bypass is working end-to-end.
    function test_RestrictedFnViaManagerExecuteAfterDelaySucceeds() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = managed.restrictedFn.selector;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(managed), selectors, CALLER_ROLE);
        vm.prank(admin);
        mgr.grantRole(CALLER_ROLE, alice, uint32(1 days)); // execution delay

        bytes memory data = abi.encodeCall(MockAccessManagedContract.restrictedFn, ());

        // Schedule the operation
        vm.prank(alice);
        (bytes32 opId,) = mgr.schedule(address(managed), data, uint48(block.timestamp + 1 days));

        // Before delay: execute must fail
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotReady.selector, opId));
        mgr.execute(address(managed), data);

        // After delay: execute must succeed (isConsumingScheduledOp bypass active)
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        mgr.execute(address(managed), data);

        // Operation consumed: schedule cleared
        assertEq(mgr.getSchedule(opId), 0);

        // isConsumingScheduledOp flag must be cleared after execution
        assertEq(managed.isConsumingScheduledOp(), bytes4(0));
    }

    /// @notice setConsumingScheduledOp must revert for non-authority callers.
    function test_SetConsumingScheduledOpByNonAuthorityReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        managed.setConsumingScheduledOp(true);
    }
}
