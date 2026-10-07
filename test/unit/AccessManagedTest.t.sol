// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AccessManagedTestBase} from "@lattice-test/base/AccessManagedTestBase.sol";
import {AccessManagedTestFacet, IAccessManagedTestHook} from "@lattice-test/helpers/AccessManagedTestFacet.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AccessManaged} from "@lattice/access/AccessManaged.sol";
import {AccessManager} from "@lattice/access/AccessManager.sol";
import {IAccessManaged} from "@lattice/interfaces/access/IAccessManaged.sol";
import {IAccessManager} from "@lattice/interfaces/access/IAccessManager.sol";

/// @notice #215 route-2 probe: notified from inside a manager-driven `execute` of
///         {AccessManagedTestFacet-restrictedNotify}, it tries to re-enter the ADMIN_ROLE-only `restrictedFn` on
///         the same target and records what the authority reports for the manager-as-caller at that moment.
contract ReentrantHook is IAccessManagedTestHook {
    address internal immutable manager;
    address internal immutable target;

    bool public notified;
    bool public reentered;
    bool public selfImmediateInFlight; // canCall(manager, target, restrictedNotify) during execute
    bool public selfImmediateOther; // canCall(manager, target, restrictedFn) during execute

    constructor(address manager_, address target_) {
        manager = manager_;
        target = target_;
    }

    function onNotify() external {
        notified = true;
        (selfImmediateInFlight,) =
            IAccessManager(manager).canCall(manager, target, AccessManagedTestFacet.restrictedNotify.selector);
        (selfImmediateOther,) =
            IAccessManager(manager).canCall(manager, target, AccessManagedTestFacet.restrictedFn.selector);
        try AccessManagedTestFacet(target).restrictedFn() {
            reentered = true;
        } catch {}
    }
}

/// @notice #215 nesting probe: notified from inside a PUBLIC_ROLE `execute` of
///         {AccessManagedTestFacet-restrictedNotify}, it runs one inner `execute` of the same call, then records what
///         the authority reports for the manager-as-caller once the inner `execute` has returned.
contract NestedHook is IAccessManagedTestHook {
    address internal immutable manager;
    address internal immutable target;

    uint256 public depth;
    bool public reentered;
    bool public outerIdRestored; // canCall(manager, target, restrictedNotify) after the inner execute

    constructor(address manager_, address target_) {
        manager = manager_;
        target = target_;
    }

    function onNotify() external {
        if (depth++ != 0) return;
        IAccessManager(manager)
            .execute(target, abi.encodeCall(AccessManagedTestFacet.restrictedNotify, (address(this))));
        (outerIdRestored,) =
            IAccessManager(manager).canCall(manager, target, AccessManagedTestFacet.restrictedNotify.selector);
        try AccessManagedTestFacet(target).restrictedFn() {
            reentered = true;
        } catch {}
    }
}

/// @title AccessManagedTest
/// @notice Exercises the AccessManaged facet through a REAL {Diamond} pair assembled by the ready-to-deploy
///         {DeployAccessManager} (authority) and {DeployAccessManaged} (managed) scripts (see
///         {AccessManagedTestBase}) — every call routes through diamond `delegatecall` dispatch, not flattened
///         mocks. The managed target's gated `restrictedFn` lives on the cut-in test-only {AccessManagedTestFacet};
///         the full authority round-trip (direct `canCall`, matured `schedule`/`execute`) is proven end-to-end.
contract AccessManagedTest is AccessManagedTestBase {
    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    uint64 constant CALLER_ROLE = 1;
    uint64 constant PUBLIC_ROLE = type(uint64).max;

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
    ///         AccessManager.execute() after the delay matures: the authority accepts itself as caller for the
    ///         (target, selector) it is executing, so `restrictedCheck` passes with no target-side bypass.
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

        // After delay: execute must succeed (the manager is the authorized caller for this execution id)
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        mgr.execute(address(managed), data);

        // Operation consumed: schedule cleared
        assertEq(mgr.getSchedule(opId), 0);

        // A manager-driven execute never touches the target's consuming flag
        assertEq(managed.isConsumingScheduledOp(), bytes4(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                  #215: EXECUTION-ID MODEL REGRESSIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice #215 route 1: migrating the target through `execute(D, setAuthority(M2))` must not leave it open.
    ///         The old consuming flag could only be cleared by the (former) authority, so after migration the clear
    ///         failed silently and every `restrictedCheck`-gated function accepted any caller.
    function test_MigrationViaExecuteDoesNotLeaveTargetOpen() public {
        address newAuthority = _deployAuthority(admin);

        // ADMIN_ROLE (0) is every selector's default role, so the admin may execute setAuthority immediately.
        vm.prank(admin);
        mgr.execute(diamond, abi.encodeCall(IAccessManaged.setAuthority, (newAuthority)));
        assertEq(managed.authority(), newAuthority);

        (bool immediate, uint32 delay) =
            AccessManager(newAuthority).canCall(bob, diamond, AccessManagedTestFacet.restrictedFn.selector);
        assertFalse(immediate);
        assertEq(delay, 0);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, bob));
        managedHelper.restrictedFn();

        assertEq(managed.isConsumingScheduledOp(), bytes4(0));
    }

    /// @notice #215 route 2: while the manager executes a PUBLIC_ROLE function on D, a callee that re-enters an
    ///         ADMIN_ROLE-only function on D is checked against its own `msg.sender` and rejected. The manager is
    ///         accepted as caller only for the (target, selector) in flight, and only for the call's duration.
    function test_PublicRoleExecuteCalleeCannotReenterAdminFunction() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = AccessManagedTestFacet.restrictedNotify.selector;
        vm.prank(admin);
        mgr.setTargetFunctionRole(diamond, selectors, PUBLIC_ROLE);

        ReentrantHook hook = new ReentrantHook(authority, diamond);

        vm.prank(bob);
        mgr.execute(diamond, abi.encodeCall(AccessManagedTestFacet.restrictedNotify, (address(hook))));

        assertTrue(hook.notified(), "hook ran");
        assertFalse(hook.reentered(), "callee re-entered an ADMIN_ROLE function");
        assertTrue(hook.selfImmediateInFlight(), "manager accepted for the in-flight selector");
        assertFalse(hook.selfImmediateOther(), "manager accepted for another selector");

        // The execution id is restored once `execute` returns.
        (bool immediate,) = mgr.canCall(authority, diamond, AccessManagedTestFacet.restrictedNotify.selector);
        assertFalse(immediate, "manager still accepted after execute");
    }

    /// @notice #215: a nested `execute` restores the enclosing call's execution id rather than clearing it, so the
    ///         outer manager-driven call stays authorized after the inner one returns and a callee still gains
    ///         nothing; the id is cleared once the outermost `execute` returns.
    function test_NestedExecuteRestoresOuterExecutionId() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = AccessManagedTestFacet.restrictedNotify.selector;
        vm.prank(admin);
        mgr.setTargetFunctionRole(diamond, selectors, PUBLIC_ROLE);

        NestedHook hook = new NestedHook(authority, diamond);

        vm.prank(bob);
        mgr.execute(diamond, abi.encodeCall(AccessManagedTestFacet.restrictedNotify, (address(hook))));

        assertEq(hook.depth(), 2, "inner execute ran");
        assertTrue(hook.outerIdRestored(), "outer execution id not restored after the inner execute");
        assertFalse(hook.reentered(), "callee re-entered an ADMIN_ROLE function");

        (bool immediate,) = mgr.canCall(authority, diamond, AccessManagedTestFacet.restrictedNotify.selector);
        assertFalse(immediate, "manager still accepted after execute");
    }

    /// @notice #215: the admin migrates a managed target with `updateAuthority`, and the old manager loses control.
    function test_UpdateAuthorityByAdminMigratesTarget() public {
        address newAuthority = _deployAuthority(admin);

        vm.expectEmit(true, false, false, false, diamond);
        emit IAccessManaged.AuthorityUpdated(newAuthority);
        vm.prank(admin);
        mgr.updateAuthority(diamond, newAuthority);
        assertEq(managed.authority(), newAuthority);

        // The old manager is no longer the target's authority, so it can neither migrate it again ...
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, authority));
        mgr.updateAuthority(diamond, authority);

        // ... nor open its functions: the new authority decides, and it has granted bob nothing.
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = AccessManagedTestFacet.restrictedFn.selector;
        vm.prank(admin);
        mgr.setTargetFunctionRole(diamond, selectors, PUBLIC_ROLE);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IAccessManaged.AccessManagedUnauthorized.selector, bob));
        managedHelper.restrictedFn();
    }

    /// @notice #215: `updateAuthority` is ADMIN_ROLE-only.
    function test_UpdateAuthorityByNonAdminReverts() public {
        address newAuthority = _deployAuthority(admin);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, alice, 0));
        mgr.updateAuthority(diamond, newAuthority);
        assertEq(managed.authority(), authority);
    }

    /// @notice #215: outside `execute`, the manager is not an authorized caller of its targets — even for a
    ///         PUBLIC_ROLE selector (OZ order: closed check, then the self branch, then the role lookup).
    function test_CanCallManagerAsCallerOutsideExecuteIsFalse() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = AccessManagedTestFacet.restrictedFn.selector;
        vm.prank(admin);
        mgr.setTargetFunctionRole(diamond, selectors, PUBLIC_ROLE);

        (bool immediate, uint32 delay) = mgr.canCall(authority, diamond, AccessManagedTestFacet.restrictedFn.selector);
        assertFalse(immediate);
        assertEq(delay, 0);

        // Any other caller still gets the PUBLIC_ROLE answer.
        (immediate, delay) = mgr.canCall(bob, diamond, AccessManagedTestFacet.restrictedFn.selector);
        assertTrue(immediate);
        assertEq(delay, 0);
    }
}
