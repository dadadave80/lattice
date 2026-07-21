// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AccessManagedTestBase} from "@lattice-test/base/AccessManagedTestBase.sol";
import {AccessManagedTestFacet} from "@lattice-test/helpers/AccessManagedTestFacet.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AccessManaged} from "@lattice/access/AccessManaged.sol";
import {AccessManager} from "@lattice/access/AccessManager.sol";
import {IAccessManaged} from "@lattice/interfaces/access/IAccessManaged.sol";
import {IAccessManager} from "@lattice/interfaces/access/IAccessManager.sol";

/// @title AccessManagedTest
/// @notice Exercises the AccessManaged facet through a REAL {Diamond} pair assembled by the ready-to-deploy
///         {DeployAccessManager} (authority) and {DeployAccessManaged} (managed) scripts (see
///         {AccessManagedTestBase}) — every call routes through diamond `delegatecall` dispatch, not flattened
///         mocks. The managed target's gated `restrictedFn` lives on the cut-in test-only {AccessManagedTestFacet};
///         the full authority round-trip (direct `canCall`, matured `schedule`/`execute`) is proven end-to-end.
contract AccessManagedTest is AccessManagedTestBase {
    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);
    uint64 constant CALLER_ROLE = 1;

    function setUp() public {
        authority = _deployAuthority(admin);
        mgr = AccessManager(authority);

        diamond = _deployManaged(authority);
        managed = AccessManaged(diamond);
        managedHelper = AccessManagedTestFacet(diamond);
    }

    function test_AuthorityIsSet() public view {
        assertEq(managed.authority(), authority);
    }

    function test_InitWithZeroAuthorityReverts() public {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = _managedCuts(address(0));
        Lattice d = new Lattice();
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedInvalidAuthority.selector, address(0)));
        d.initialize(cuts, init, initCalldata);
    }

    function test_SetAuthorityByNonAuthorityReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        managed.setAuthority(address(0x123));
    }

    function test_SetAuthorityByAuthorityWorks() public {
        address newAuthority = _deployAuthority(admin);
        vm.prank(authority);
        managed.setAuthority(newAuthority);
        assertEq(managed.authority(), newAuthority);
    }

    function test_SetAuthorityEOAReverts() public {
        address eoa = address(0xDEAD);
        vm.prank(authority);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedInvalidAuthority.selector, eoa));
        managed.setAuthority(eoa);
    }

    function test_InitWithEOAAuthorityReverts() public {
        address eoa = address(0xBEEF);
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = _managedCuts(eoa);
        Lattice d = new Lattice();
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedInvalidAuthority.selector, eoa));
        d.initialize(cuts, init, initCalldata);
    }

    function test_RestrictedFnUnauthorizedReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, alice));
        managedHelper.restrictedFn();
    }

    function test_RestrictedFnAuthorizedPasses() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = managedHelper.restrictedFn.selector;
        vm.prank(admin);
        mgr.setTargetFunctionRole(address(managed), selectors, type(uint64).max);

        vm.prank(alice);
        managedHelper.restrictedFn();
    }

    /// @notice T-1 / H-1 regression: a caller with an execution delay gets
    ///         AccessManagedRequiredDelay when calling directly (without schedule+execute).
    function test_RestrictedFnWithDelayRevertsDirectly() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = managedHelper.restrictedFn.selector;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(managed), selectors, CALLER_ROLE);
        vm.prank(admin);
        mgr.grantRole(CALLER_ROLE, alice, uint32(1 days)); // execution delay

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessManaged.AccessManagedRequiredDelay.selector, alice, uint32(1 days))
        );
        managedHelper.restrictedFn();
    }

    /// @notice T-1 / H-1 regression: a caller with an execution delay can succeed through
    ///         AccessManager.execute() after the delay matures. Verifies the _consumingScheduledOp
    ///         bypass is working end-to-end.
    function test_RestrictedFnViaManagerExecuteAfterDelaySucceeds() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = managedHelper.restrictedFn.selector;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(managed), selectors, CALLER_ROLE);
        vm.prank(admin);
        mgr.grantRole(CALLER_ROLE, alice, uint32(1 days)); // execution delay

        bytes memory data = abi.encodeCall(AccessManagedTestFacet.restrictedFn, ());

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
