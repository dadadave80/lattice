// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IInvariantChecker} from "@lattice/interfaces/security/IInvariantChecker.sol";
import {InvariantChecker} from "@lattice/security/InvariantChecker.sol";
import {InvariantCheckerLib} from "@lattice/security/libraries/InvariantCheckerLib.sol";
import {Test} from "forge-std/Test.sol";

// =============================================================================
// Worked example: wiring InvariantChecker to a real protocol invariant.
//
// Lattice ships no protocol of its own, so it registers no default invariants.
// InvariantChecker is an *opt-in* safety facet: a consumer registers
// (key -> target + selector) pairs pointing at their own bool-returning view
// functions, then gates sensitive operations on `checkInvariant` /
// `checkInvariants`. This file is the canonical, copyable reference for that
// pattern, exercised against a solvency-style invariant.
// =============================================================================

/// @notice A minimal consumer treasury that exposes a solvency invariant.
/// @dev `isSolvent()` is exactly the kind of bool-returning view a consumer
///      registers with InvariantChecker: tracked backing must cover liabilities.
contract MockTreasury {
    uint256 public backing;
    uint256 public liabilities;

    constructor(uint256 _backing, uint256 _liabilities) {
        backing = _backing;
        liabilities = _liabilities;
    }

    /// @notice The protocol invariant: assets backing the treasury must always
    ///         be at least as large as outstanding liabilities.
    /// @return Whether the treasury is solvent.
    function isSolvent() external view returns (bool) {
        return backing >= liabilities;
    }

    /// @dev Test hook to push the treasury underwater (mint unbacked liability).
    function borrowUnbacked(uint256 amount) external {
        liabilities += amount;
    }

    /// @dev Test hook to restore solvency (top up backing).
    function deposit(uint256 amount) external {
        backing += amount;
    }
}

/// @title MockSolventProtocol
/// @notice A consumer Diamond facet combining InvariantChecker + AccessControl,
///         demonstrating how a real protocol would gate an action on its own
///         registered invariant.
contract MockSolventProtocol is InvariantChecker, AccessControl {
    /// @notice Initializes AccessControl and InvariantChecker for this consumer.
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        InvariantCheckerLib.__InvariantChecker_init();
        InitializableLib.postInitializer(s);
    }

    /// @notice A sensitive action gated on the consumer's own solvency invariant:
    ///         it reverts (via InvariantChecker) if the protocol is insolvent.
    /// @dev This is the opt-in usage pattern — the consumer chooses which key(s)
    ///      to assert before performing state-changing work.
    function distributeYield(bytes32 solvencyKey) external view {
        InvariantCheckerLib.checkInvariant(solvencyKey);
        // ... real protocol would perform the distribution here ...
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title InvariantCheckerUsageTest
/// @notice Executable documentation: the end-to-end opt-in pattern for wiring
///         InvariantChecker to a consumer-defined protocol invariant. Covers the
///         happy path (invariant holds), the violation path (invariant broken),
///         batch checking, and the admin-only registration guard.
contract InvariantCheckerUsageTest is Test {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 private constant SOLVENCY_KEY = keccak256("lattice.invariant.treasury.solvency");

    MockSolventProtocol internal protocol;
    MockTreasury internal treasury;

    address internal admin = address(0xA11CE);
    address internal attacker = address(0xBAD);

    function setUp() public {
        protocol = new MockSolventProtocol();
        protocol.initialize(admin);

        // Treasury starts solvent: 1_000 backing against 600 liabilities.
        treasury = new MockTreasury(1_000, 600);
    }

    // -------------------------------------------------------------------------
    // Step 1 — the admin (governance) wires the consumer's invariant.
    // -------------------------------------------------------------------------

    /// @notice Registration is the consumer's opt-in: governance points a key at
    ///         its own `isSolvent()` view. Only DEFAULT_ADMIN_ROLE may do this.
    function test_RegisterSolvencyInvariant() public {
        vm.prank(admin);
        protocol.registerInvariant(SOLVENCY_KEY, address(treasury), MockTreasury.isSolvent.selector);

        (address target, bytes4 selector) = protocol.getInvariant(SOLVENCY_KEY);
        assertEq(target, address(treasury));
        assertEq(selector, MockTreasury.isSolvent.selector);
    }

    /// @notice A non-admin cannot register an invariant — registration is gated.
    function test_RegisterByNonAdminReverts() public {
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, DEFAULT_ADMIN_ROLE
            )
        );
        protocol.registerInvariant(SOLVENCY_KEY, address(treasury), MockTreasury.isSolvent.selector);
    }

    // -------------------------------------------------------------------------
    // Step 2 — happy path: the invariant holds, gated action succeeds.
    // -------------------------------------------------------------------------

    /// @notice While `backing >= liabilities`, `checkInvariant` passes and the
    ///         consumer's gated action proceeds.
    function test_GatedActionSucceedsWhileSolvent() public {
        vm.prank(admin);
        protocol.registerInvariant(SOLVENCY_KEY, address(treasury), MockTreasury.isSolvent.selector);

        // Direct check passes.
        protocol.checkInvariant(SOLVENCY_KEY);

        // And so does the action that gates on it (anyone may trigger the check).
        vm.prank(attacker);
        protocol.distributeYield(SOLVENCY_KEY);
    }

    /// @notice At the exact boundary (backing == liabilities) the protocol is
    ///         still solvent, so the check must pass.
    function test_GatedActionSucceedsAtSolvencyBoundary() public {
        treasury = new MockTreasury(600, 600); // backing == liabilities
        vm.prank(admin);
        protocol.registerInvariant(SOLVENCY_KEY, address(treasury), MockTreasury.isSolvent.selector);

        protocol.distributeYield(SOLVENCY_KEY); // must not revert
    }

    // -------------------------------------------------------------------------
    // Step 3 — violation path: the invariant breaks, the action is blocked.
    // -------------------------------------------------------------------------

    /// @notice Once liabilities exceed backing, `checkInvariant` reverts with the
    ///         exact `InvariantViolatedError` selector, and the gated action is
    ///         blocked.
    function test_GatedActionRevertsWhenInsolvent() public {
        vm.prank(admin);
        protocol.registerInvariant(SOLVENCY_KEY, address(treasury), MockTreasury.isSolvent.selector);

        // Push the treasury underwater: 1_000 backing, 1_001 liabilities.
        treasury.borrowUnbacked(401);

        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantViolatedError.selector, SOLVENCY_KEY));
        protocol.checkInvariant(SOLVENCY_KEY);

        // The consumer's gated action inherits the same revert.
        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantViolatedError.selector, SOLVENCY_KEY));
        protocol.distributeYield(SOLVENCY_KEY);
    }

    /// @notice Solvency can be restored and the gate re-opens — the check tracks
    ///         live state, it is not a one-shot latch.
    function test_GateReopensAfterSolvencyRestored() public {
        vm.prank(admin);
        protocol.registerInvariant(SOLVENCY_KEY, address(treasury), MockTreasury.isSolvent.selector);

        treasury.borrowUnbacked(500); // insolvent: 1_000 < 1_100
        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantViolatedError.selector, SOLVENCY_KEY));
        protocol.checkInvariant(SOLVENCY_KEY);

        treasury.deposit(200); // solvent again: 1_200 >= 1_100
        protocol.checkInvariant(SOLVENCY_KEY); // must not revert
    }

    // -------------------------------------------------------------------------
    // Step 4 — batch: assert several invariants atomically before an action.
    // -------------------------------------------------------------------------

    /// @notice A consumer can assert a whole suite of invariants in one call;
    ///         `checkInvariants` reverts on the first violation.
    function test_BatchCheckRevertsOnInsolventMember() public {
        MockTreasury reserveA = new MockTreasury(500, 100); // solvent
        MockTreasury reserveB = new MockTreasury(100, 900); // insolvent

        bytes32 keyA = keccak256("reserveA.solvency");
        bytes32 keyB = keccak256("reserveB.solvency");

        vm.startPrank(admin);
        protocol.registerInvariant(keyA, address(reserveA), MockTreasury.isSolvent.selector);
        protocol.registerInvariant(keyB, address(reserveB), MockTreasury.isSolvent.selector);
        vm.stopPrank();

        bytes32[] memory keys = new bytes32[](2);
        keys[0] = keyA;
        keys[1] = keyB;

        vm.expectRevert(abi.encodeWithSelector(IInvariantChecker.InvariantViolatedError.selector, keyB));
        protocol.checkInvariants(keys);
    }
}
