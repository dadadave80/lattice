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

    /// @notice T-1 / H-1 regression: a caller with an execution delay cannot call directly without a matured
    ///         schedule: the target asks the authority to consume one, and there is none (#219, OZ semantics).
    function test_RestrictedFnWithDelayRevertsDirectly() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = managedHelper.restrictedFn.selector;

        vm.prank(admin);
        mgr.setTargetFunctionRole(address(managed), selectors, CALLER_ROLE);
        vm.prank(admin);
        mgr.grantRole(CALLER_ROLE, alice, uint32(1 days)); // execution delay

        bytes32 opId = mgr.hashOperation(alice, diamond, abi.encodeCall(AccessManagedTestFacet.restrictedFn, ()));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        managedHelper.restrictedFn();
    }

    /// @notice #219: a delayed caller may schedule the call and then make it directly once ready. The target sets
    ///         its consuming flag around `consumeScheduledOp`, the authority checks it, and the schedule is spent.
    function test_RestrictedFnWithDelayDirectCallConsumesSchedule() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = managedHelper.restrictedFn.selector;

        vm.prank(admin);
        mgr.setTargetFunctionRole(diamond, selectors, CALLER_ROLE);
        vm.prank(admin);
        mgr.grantRole(CALLER_ROLE, alice, uint32(1 days));

        bytes memory data = abi.encodeCall(AccessManagedTestFacet.restrictedFn, ());
        vm.prank(alice);
        (bytes32 opId, uint32 nonce) = mgr.schedule(diamond, data, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotReady.selector, opId));
        managedHelper.restrictedFn();

        vm.warp(block.timestamp + 1 days);
        vm.expectEmit(true, true, false, false, authority);
        emit IAccessManager.OperationExecuted(opId, nonce);
        vm.prank(alice);
        managedHelper.restrictedFn();

        assertEq(mgr.getSchedule(opId), 0, "schedule consumed");
        assertEq(managed.isConsumingScheduledOp(), bytes4(0), "flag cleared after the call");

        // Spent: a second direct call has nothing to consume.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        managedHelper.restrictedFn();
    }

    /// @notice #219: a target can consume only operations scheduled against itself, and only while consuming.
    function test_ConsumeScheduledOpOutsideRestrictedCheckReverts() public {
        vm.prank(diamond);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedConsume.selector, diamond));
        mgr.consumeScheduledOp(alice, abi.encodeCall(AccessManagedTestFacet.restrictedFn, ()));
    }

    /// @notice #219: a delayed direct call whose schedule has expired reverts with the authority's
    ///         `AccessManagerExpired`, bubbled up through `consumeScheduledOp`.
    function test_RestrictedFnWithDelayDirectCallRevertsWhenExpired() public {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = managedHelper.restrictedFn.selector;
        vm.prank(admin);
        mgr.setTargetFunctionRole(diamond, selectors, CALLER_ROLE);
        vm.prank(admin);
        mgr.grantRole(CALLER_ROLE, alice, uint32(1 days));

        vm.prank(alice);
        (bytes32 opId,) = mgr.schedule(diamond, abi.encodeCall(AccessManagedTestFacet.restrictedFn, ()), 0);
        uint48 readyAt = mgr.getSchedule(opId);

        vm.warp(uint256(readyAt) + 1 weeks);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerExpired.selector, opId));
        managedHelper.restrictedFn();
        assertEq(managed.isConsumingScheduledOp(), bytes4(0));
    }

    /// @notice #219: `updateAuthority` carries the managed target's admin delay. On its own this is no exit window:
    ///         see {test_ExecuteSetAuthority_BypassesAdminDelayWhileSelectorIsAdminRole}.
    function test_UpdateAuthorityRespectsTargetAdminDelay() public {
        address newAuthority = _deployAuthority(admin);
        vm.prank(admin);
        mgr.setTargetAdminDelay(diamond, 1 days);
        vm.warp(block.timestamp + 5 days);

        bytes memory data = abi.encodeCall(IAccessManager.updateAuthority, (diamond, newAuthority));
        bytes32 opId = mgr.hashOperation(admin, authority, data);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, opId));
        mgr.updateAuthority(diamond, newAuthority);

        vm.prank(admin);
        mgr.schedule(authority, data, 0);
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        mgr.execute(authority, data);
        assertEq(managed.authority(), newAuthority);
    }

    /// @notice #219 characterization (OZ v5.1.0 parity): while the target's `setAuthority` selector keeps the default
    ///         ADMIN_ROLE, an admin migrates it at once with `execute(target, setAuthority(x))`. That call is gated by
    ///         the target's function roles, not by the admin restriction on `updateAuthority`, so the admin delay
    ///         does not apply to it.
    function test_ExecuteSetAuthority_BypassesAdminDelayWhileSelectorIsAdminRole() public {
        address newAuthority = _deployAuthority(admin);
        vm.prank(admin);
        mgr.setTargetAdminDelay(diamond, 7 days);
        vm.warp(block.timestamp + 7 days);
        assertEq(mgr.getTargetAdminDelay(diamond), 7 days);

        vm.prank(admin);
        mgr.execute(diamond, abi.encodeCall(IAccessManaged.setAuthority, (newAuthority)));
        assertEq(managed.authority(), newAuthority);
    }

    /// @notice #219: mapping the target's `setAuthority` to a role nobody holds closes the `execute` route, leaves
    ///         `updateAuthority` (with its admin delay) as the only migration path, and undoing the mapping is itself
    ///         held back by the admin delay.
    function test_ExecuteSetAuthority_BlockedOnceSelectorMappedToUnheldRole() public {
        uint64 noOne = 99;
        address newAuthority = _deployAuthority(admin);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IAccessManaged.setAuthority.selector;
        vm.prank(admin);
        mgr.setTargetFunctionRole(diamond, selectors, noOne);
        vm.prank(admin);
        mgr.setTargetAdminDelay(diamond, 7 days);
        vm.warp(block.timestamp + 7 days);

        bytes memory setAuthorityCall = abi.encodeCall(IAccessManaged.setAuthority, (newAuthority));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, admin, noOne));
        mgr.execute(diamond, setAuthorityCall);

        // Remapping the selector back is a target-configuration change, so it waits out the admin delay too.
        bytes32 remapId = mgr.hashOperation(
            admin, authority, abi.encodeCall(IAccessManager.setTargetFunctionRole, (diamond, selectors, uint64(0)))
        );
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerNotScheduled.selector, remapId));
        mgr.setTargetFunctionRole(diamond, selectors, 0);
        assertEq(mgr.getTargetFunctionRole(diamond, IAccessManaged.setAuthority.selector), noOne);

        // The delayed `updateAuthority` still migrates the target.
        bytes memory update = abi.encodeCall(IAccessManager.updateAuthority, (diamond, newAuthority));
        vm.prank(admin);
        mgr.schedule(authority, update, 0);
        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        mgr.execute(authority, update);
        assertEq(managed.authority(), newAuthority);
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
