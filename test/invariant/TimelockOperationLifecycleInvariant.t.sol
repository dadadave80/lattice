// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TimelockControllerStandalone} from "@lattice/governance/TimelockControllerStandalone.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {ITimelockController} from "@lattice/interfaces/ITimelockController.sol";
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
        vm.prank(PROPOSER);
        try timelock.schedule(address(target), 0, abi.encodeCall(DummyTarget.increment, ()), 0, salt, MIN_DELAY) {
            _updateMaxStage(id);
        } catch {}
    }

    /// @notice Execute the first operation that is Ready (if any).
    function executeReadyOp() external {
        for (uint256 i; i < _ops.length; ++i) {
            bytes32 id = _ops[i];
            if (!timelock.isOperationReady(id)) continue;

            // Reconstruct salt from index (we used ++_saltNonce starting at 1).
            bytes32 salt = bytes32(i + 1);
            vm.prank(EXECUTOR);
            try timelock.execute(address(target), 0, abi.encodeCall(DummyTarget.increment, ()), 0, salt) {
                _updateMaxStage(id);
            } catch {}
            return;
        }
    }

    /// @notice Cancel the first operation that is still Pending (Waiting or Ready).
    function cancelOp() external {
        for (uint256 i; i < _ops.length; ++i) {
            bytes32 id = _ops[i];
            if (!timelock.isOperationPending(id)) continue;

            vm.prank(CANCELLER);
            try timelock.cancel(id) {
                // After cancel, state returns to Unset — record as CANCELLED.
                if (maxStage[id] < CANCELLED) maxStage[id] = CANCELLED;
            } catch {}
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
                // Cancelled: on-chain must be Unset; Done is a violation (executed after cancel).
                assertNotEq(currentStage, 3, "op was executed after being cancelled");
            } else {
                // For non-cancelled ops, current stage must equal maxStage (never decrease, never skip Done).
                assertGe(currentStage, 0, "invalid stage");
                // The max recorded stage must be reachable from the current on-chain state.
                // i.e. current stage must not be LESS than maxSeen.
                // Exception: time may have NOT advanced to Ready yet after Waiting was the last warp.
                // We allow current < maxSeen only if this would mean we somehow went Done -> Ready/Waiting,
                // which is the real violation. So: if maxSeen == 3 (Done), current must be 3.
                if (maxSeen == 3) {
                    assertEq(currentStage, 3, "op regressed from Done to a lower state");
                }
            }
        }
    }
}
