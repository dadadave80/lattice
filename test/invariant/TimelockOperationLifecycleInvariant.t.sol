// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TimelockControllerStandalone} from "@lattice/governance/TimelockControllerStandalone.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {ITimelockController} from "@lattice/interfaces/governance/ITimelockController.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                               DUMMY TARGET
//////////////////////////////////////////////////////////////////////////*//

/// @notice Trivial call target that always succeeds.
contract DummyTarget {
    uint256 public counter;

    function increment() external {
        ++counter;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Handler for timelock lifecycle invariant testing.
/// @dev Every action is authorised and state-checked first, so a revert means a broken lifecycle and fails the run
///      under `fail_on_revert`.
contract TimelockLifecycleHandler is Test {
    TimelockControllerStandalone public timelock;
    DummyTarget public target;

    address public immutable ADMIN;
    address public immutable PROPOSER;
    address public immutable EXECUTOR;
    address public immutable CANCELLER;

    uint256 constant MIN_DELAY = 1 hours;

    /// @notice OperationState numeric values — match ITimelockController.OperationState enum order.
    uint8 constant UNSET = 0;
    uint8 constant WAITING = 1;
    uint8 constant READY = 2;
    uint8 constant DONE = 3;
    uint8 constant CANCELLED = 4; // synthetic stage used by this handler only

    /// @notice Tracked operation IDs.
    bytes32[] internal _ops;
    mapping(bytes32 => bool) internal _opSeen;

    /// @notice Highest stage ever observed for each operation ID.
    mapping(bytes32 => uint8) public maxStage;

    /// @notice Salt each tracked operation was scheduled with.
    mapping(bytes32 => bytes32) internal _saltOf;

    /// @notice Salt counter — incremented to produce unique op IDs.
    uint256 internal _saltNonce;

    constructor(
        TimelockControllerStandalone timelock_,
        DummyTarget target_,
        address admin_,
        address proposer_,
        address executor_,
        address canceller_
    ) {
        timelock = timelock_;
        target = target_;
        ADMIN = admin_;
        PROPOSER = proposer_;
        EXECUTOR = executor_;
        CANCELLER = canceller_;
    }

    function trackedOps() external view returns (bytes32[] memory) {
        return _ops;
    }

    function _trackOp(bytes32 id) internal {
        if (!_opSeen[id]) {
            _opSeen[id] = true;
            _ops.push(id);
        }
    }

    /// @notice Convert the on-chain OperationState to our numeric stage.
    function _stage(bytes32 id) internal view returns (uint8) {
        ITimelockController.OperationState state = timelock.getOperationState(id);
        if (state == ITimelockController.OperationState.Done) return DONE;
        if (state == ITimelockController.OperationState.Ready) return READY;
        if (state == ITimelockController.OperationState.Waiting) return WAITING;
        // Unset — but if we previously saw it as Cancelled (Unset after cancel), keep CANCELLED.
        if (maxStage[id] == CANCELLED) return CANCELLED;
        return UNSET;
    }

    /// @notice Update the maxStage ghost for an operation after each action.
    function _updateMaxStage(bytes32 id) internal {
        uint8 current = _stage(id);
        if (current > maxStage[id]) {
            maxStage[id] = current;
        }
    }

    /// @notice Schedule a brand-new operation with a unique salt.
    function scheduleNewOp() external {
        bytes32 salt = bytes32(++_saltNonce);
        bytes32 id = timelock.hashOperation(address(target), 0, abi.encodeCall(DummyTarget.increment, ()), 0, salt);
        // Skip if already scheduled.
        if (timelock.isOperation(id)) return;

        _trackOp(id);
        _saltOf[id] = salt;
        vm.prank(PROPOSER);
        timelock.schedule(address(target), 0, abi.encodeCall(DummyTarget.increment, ()), 0, salt, MIN_DELAY);
        // A non-zero delay must hold a fresh op in Waiting; Ready here means the delay was skipped.
        assertEq(uint8(timelock.getOperationState(id)), WAITING, "scheduled op not Waiting");
        _updateMaxStage(id);
    }

    /// @notice Execute the first Ready operation at or after a fuzzed start index (if any).
    function executeReadyOp(uint256 startSeed) external {
        uint256 n = _ops.length;
        for (uint256 k; k < n; ++k) {
            bytes32 id = _ops[(startSeed % n + k) % n];
            if (!timelock.isOperationReady(id)) continue;

            vm.prank(EXECUTOR);
            timelock.execute(address(target), 0, abi.encodeCall(DummyTarget.increment, ()), 0, _saltOf[id]);
            // An executed op must be Done; one left Ready could be replayed.
            assertTrue(timelock.isOperationDone(id), "executed op not Done");
            _updateMaxStage(id);
            return;
        }
    }

    /// @notice Cancel the first Pending (Waiting or Ready) operation at or after a fuzzed start index (if any).
    function cancelOp(uint256 startSeed) external {
        uint256 n = _ops.length;
        for (uint256 k; k < n; ++k) {
            bytes32 id = _ops[(startSeed % n + k) % n];
            if (!timelock.isOperationPending(id)) continue;

            vm.prank(CANCELLER);
            timelock.cancel(id);
            // After cancel, state returns to Unset — record as CANCELLED.
            maxStage[id] = CANCELLED;
            return;
        }
    }

    /// @notice Advance time by a fuzzed amount (bounded to accelerate through the delay).
    function warpTime(uint256 delta) external {
        delta = bound(delta, 0, 2 * MIN_DELAY);
        vm.warp(block.timestamp + delta);
        // Refresh stages of all tracked ops after the warp.
        for (uint256 i; i < _ops.length; ++i) {
            _updateMaxStage(_ops[i]);
        }
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               INVARIANT TEST
//////////////////////////////////////////////////////////////////////////*//

/// @title TimelockOperationLifecycleInvariant
/// @notice Invariant: operation state transitions are monotonically forward-only.
///         Unset -> Waiting -> Ready -> Done (or -> Cancelled).
///         No operation may regress to an earlier stage.
contract TimelockOperationLifecycleInvariant is Test {
    TimelockControllerStandalone internal timelock;
    DummyTarget internal dummyTarget;
    TimelockLifecycleHandler internal handler;

    address internal admin = address(0xEAD);
    address internal proposer = address(0xEA1);
    address internal executor = address(0xEA2);
    address internal canceller = address(0xEA3);

    function setUp() public {
        dummyTarget = new DummyTarget();

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        // Also grant CANCELLER_ROLE to the canceller address.
        address[] memory executors = new address[](1);
        executors[0] = executor;

        timelock = new TimelockControllerStandalone(1 hours, proposers, executors, admin);

        // Grant CANCELLER_ROLE to canceller.
        vm.prank(admin);
        timelock.grantRole(TimelockControllerLib.CANCELLER_ROLE, canceller);

        handler = new TimelockLifecycleHandler(timelock, dummyTarget, admin, proposer, executor, canceller);
        targetContract(address(handler));
    }

    /// @notice Each operation's current stage must be >= the highest stage ever seen for it.
    /// This enforces that state transitions only move forward.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_OperationStateMonotonic() public view {
        bytes32[] memory ops = handler.trackedOps();
        for (uint256 i; i < ops.length; ++i) {
            bytes32 id = ops[i];
            ITimelockController.OperationState onChain = timelock.getOperationState(id);

            uint8 currentStage;
            if (onChain == ITimelockController.OperationState.Done) currentStage = 3;
            else if (onChain == ITimelockController.OperationState.Ready) currentStage = 2;
            else if (onChain == ITimelockController.OperationState.Waiting) currentStage = 1;
            else currentStage = 0; // Unset — either never scheduled or cancelled

            uint8 maxSeen = handler.maxStage(id);

            // A cancelled op ends at Unset on-chain but its maxStage is CANCELLED (4).
            // On-chain Unset is valid only if the op was never scheduled (maxSeen=0) or was cancelled (maxSeen=4).
            // An on-chain Done (3) must have maxStage 3. An on-chain Ready (2) must have maxStage >= 2, etc.
            if (maxSeen == 4) {
                // Cancelled: on-chain must stay Unset (the handler never reuses a salt); Done would mean the op
                // executed after being cancelled.
                assertEq(currentStage, 0, "cancelled op left Unset");
            } else {
                // For non-cancelled ops the on-chain stage never falls below the highest stage seen: time only
                // moves forward, so Waiting -> Ready -> Done never reverses (e.g. Ready -> Waiting, Done -> Ready).
                assertGe(currentStage, maxSeen, "op regressed to an earlier stage");
            }
        }
    }
}
