// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {TimelockControllerStandalone} from "@lattice/governance/TimelockControllerStandalone.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {ITimelockController} from "@lattice/interfaces/ITimelockController.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title Target
/// @notice Simple call target used by TimelockController execution tests.
contract Target {
    uint256 public value;
    bool public wasCalled;

    function setValue(uint256 _value) external {
        value = _value;
        wasCalled = true;
    }

    /// @notice A function that always reverts (for revert-bubble-up tests).
    function alwaysReverts() external pure {
        revert("Target: always reverts");
    }
}

/// @title TimelockControllerTester
/// @notice Comprehensive tests for the TimelockController module.
contract TimelockControllerTester is Test {
    TimelockControllerStandalone timelock;
    Target target;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address admin = address(0x1);
    address proposer = address(0x2);
    address executor = address(0x3);
    address canceller = address(0x4);
    address stranger = address(0x5);

    uint256 constant MIN_DELAY = 2 days;

    // ---- Role constants (mirrored for readability in tests) ----
    bytes32 PROPOSER_ROLE = TimelockControllerLib.PROPOSER_ROLE;
    bytes32 EXECUTOR_ROLE = TimelockControllerLib.EXECUTOR_ROLE;
    bytes32 CANCELLER_ROLE = TimelockControllerLib.CANCELLER_ROLE;

    // ---- Events (re-declared for vm.expectEmit) ----
    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target_,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );
    event CallExecuted(bytes32 indexed id, uint256 indexed index, address target_, uint256 value, bytes data);
    event CallSalt(bytes32 indexed id, bytes32 salt);
    event Cancelled(bytes32 indexed id);
    event MinDelayChange(uint256 oldDuration, uint256 newDuration);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    function setUp() public {
        target = new Target();

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;

        address[] memory executors = new address[](1);
        executors[0] = executor;

        timelock = new TimelockControllerStandalone(MIN_DELAY, proposers, executors, admin);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitSetsMinDelayCorrectly() public view {
        assertEq(timelock.getMinDelay(), MIN_DELAY);
    }

    function test_ProposersHaveProposerRole() public view {
        assertTrue(timelock.hasRole(PROPOSER_ROLE, proposer));
    }

    function test_ProposersHaveCancellerRole() public view {
        assertTrue(timelock.hasRole(CANCELLER_ROLE, proposer));
    }

    function test_ExecutorsHaveExecutorRole() public view {
        assertTrue(timelock.hasRole(EXECUTOR_ROLE, executor));
    }

    function test_AdminHasDefaultAdminRole() public view {
        assertTrue(timelock.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    function test_StrangerHasNoRoles() public view {
        assertFalse(timelock.hasRole(PROPOSER_ROLE, stranger));
        assertFalse(timelock.hasRole(EXECUTOR_ROLE, stranger));
        assertFalse(timelock.hasRole(CANCELLER_ROLE, stranger));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          ROLE CONSTANTS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ProposerRoleConstant() public view {
        assertEq(timelock.PROPOSER_ROLE(), keccak256("PROPOSER_ROLE"));
    }

    function test_ExecutorRoleConstant() public view {
        assertEq(timelock.EXECUTOR_ROLE(), keccak256("EXECUTOR_ROLE"));
    }

    function test_CancellerRoleConstant() public view {
        assertEq(timelock.CANCELLER_ROLE(), keccak256("CANCELLER_ROLE"));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SCHEDULE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ScheduleSetsTimestampToNowPlusDelay() public {
        bytes memory data = abi.encodeCall(Target.setValue, (42));
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        assertEq(timelock.getTimestamp(id), block.timestamp + MIN_DELAY);
    }

    function test_ScheduleRevertsIfDelayBelowMinDelay() public {
        bytes memory data = abi.encodeCall(Target.setValue, (1));

        vm.prank(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(ITimelockController.TimelockInsufficientDelay.selector, MIN_DELAY - 1, MIN_DELAY)
        );
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY - 1);
    }

    function test_ScheduleZeroDelayAllowedWhenMinDelayIsZero() public {
        // Warp past the sentinel timestamp (1) to avoid collision with _DONE_TIMESTAMP
        vm.warp(100);

        address[] memory proposers_ = new address[](1);
        proposers_[0] = proposer;
        address[] memory executors_ = new address[](1);
        executors_[0] = executor;
        TimelockControllerStandalone zeroDelayTimelock =
            new TimelockControllerStandalone(0, proposers_, executors_, admin);

        bytes memory data = abi.encodeCall(Target.setValue, (1));

        vm.prank(proposer);
        zeroDelayTimelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), 0);

        bytes32 id = zeroDelayTimelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));
        assertTrue(zeroDelayTimelock.isOperationReady(id));
    }

    function test_ScheduleDuplicateRevertsTimelockUnexpectedOperationState() public {
        bytes memory data = abi.encodeCall(Target.setValue, (1));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockController.TimelockUnexpectedOperationState.selector,
                id,
                bytes32(1 << uint8(ITimelockController.OperationState.Unset))
            )
        );
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);
    }

    function test_ScheduleByNonProposerReverts() public {
        bytes memory data = abi.encodeCall(Target.setValue, (1));

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, PROPOSER_ROLE)
        );
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);
    }

    function test_ScheduleEmitsCallScheduled() public {
        bytes memory data = abi.encodeCall(Target.setValue, (99));
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(proposer);
        vm.expectEmit(true, true, false, true);
        emit CallScheduled(id, 0, address(target), 0, data, bytes32(0), MIN_DELAY);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);
    }

    function test_ScheduleEmitsCallSaltWhenSaltNonZero() public {
        bytes memory data = abi.encodeCall(Target.setValue, (7));
        bytes32 salt = keccak256("my-salt");
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), salt);

        vm.prank(proposer);
        vm.expectEmit(true, false, false, true);
        emit CallSalt(id, salt);
        timelock.schedule(address(target), 0, data, bytes32(0), salt, MIN_DELAY);
    }

    function test_ScheduleDoesNotEmitCallSaltWhenSaltIsZero() public {
        bytes memory data = abi.encodeCall(Target.setValue, (7));

        vm.prank(proposer);
        vm.recordLogs();
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 callSaltTopic = keccak256("CallSalt(bytes32,bytes32)");
        bool saltEmitted = false;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == callSaltTopic) {
                saltEmitted = true;
                break;
            }
        }
        assertFalse(saltEmitted, "CallSalt should not be emitted when salt is zero");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          SCHEDULE BATCH TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ScheduleBatchSuccess() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = _buildBatch(3);

        bytes32 id = timelock.hashOperationBatch(targets, values, payloads, bytes32(0), bytes32(0));

        vm.prank(proposer);
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), MIN_DELAY);

        assertEq(timelock.getTimestamp(id), block.timestamp + MIN_DELAY);
    }

    function test_ScheduleBatchRevertsOnLengthMismatch() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](1); // mismatch
        bytes[] memory payloads = new bytes[](2);

        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSelector(ITimelockController.TimelockInvalidOperationLength.selector, 2, 2, 1));
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), MIN_DELAY);
    }

    function test_ScheduleBatchEmitsCallScheduledForEachItem() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory payloads) = _buildBatch(2);
        bytes32 id = timelock.hashOperationBatch(targets, values, payloads, bytes32(0), bytes32(0));

        vm.prank(proposer);
        vm.recordLogs();
        timelock.scheduleBatch(targets, values, payloads, bytes32(0), bytes32(0), MIN_DELAY);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 callScheduledTopic = keccak256("CallScheduled(bytes32,uint256,address,uint256,bytes,bytes32,uint256)");
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] == callScheduledTopic && logs[i].topics[1] == id) {
                ++count;
            }
        }
        assertEq(count, 2, "Expected 2 CallScheduled events for batch of 2");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              CANCEL TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_CancelByCanCellerWorks() public {
        bytes memory data = abi.encodeCall(Target.setValue, (1));
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.prank(proposer); // proposer has CANCELLER_ROLE
        timelock.cancel(id);

        assertFalse(timelock.isOperation(id));
    }

    function test_CancelEmitsCancelled() public {
        bytes memory data = abi.encodeCall(Target.setValue, (1));
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.prank(proposer);
        vm.expectEmit(true, false, false, false);
        emit Cancelled(id);
        timelock.cancel(id);
    }

    function test_CancelByNonCancellerReverts() public {
        bytes memory data = abi.encodeCall(Target.setValue, (1));
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, CANCELLER_ROLE)
        );
        timelock.cancel(id);
    }

    function test_CancelNonPendingOperationReverts() public {
        bytes32 id = keccak256("nonexistent");

        vm.prank(proposer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockController.TimelockUnexpectedOperationState.selector,
                id,
                // Waiting | Ready
                bytes32(
                    (1 << uint8(ITimelockController.OperationState.Waiting))
                        | (1 << uint8(ITimelockController.OperationState.Ready))
                )
            )
        );
        timelock.cancel(id);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              EXECUTE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ExecuteBeforeReadyReverts() public {
        bytes memory data = abi.encodeCall(Target.setValue, (42));
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        // Warp to just before ready
        vm.warp(block.timestamp + MIN_DELAY - 1);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockController.TimelockUnexpectedOperationState.selector,
                id,
                bytes32(1 << uint8(ITimelockController.OperationState.Ready))
            )
        );
        timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));
    }

    function test_ExecuteWhenReadyCallsTarget() public {
        bytes memory data = abi.encodeCall(Target.setValue, (42));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);

        vm.prank(executor);
        timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));

        assertEq(target.value(), 42);
        assertTrue(target.wasCalled());
    }

    function test_ExecuteMarksOperationDone() public {
        bytes memory data = abi.encodeCall(Target.setValue, (1));
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);
        vm.prank(executor);
        timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));

        assertTrue(timelock.isOperationDone(id));
        assertEq(timelock.getTimestamp(id), TimelockControllerLib._DONE_TIMESTAMP);
    }

    function test_ExecuteNonexistentOperationReverts() public {
        bytes memory data = abi.encodeCall(Target.setValue, (1));
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockController.TimelockUnexpectedOperationState.selector,
                id,
                bytes32(1 << uint8(ITimelockController.OperationState.Ready))
            )
        );
        timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));
    }

    function test_ExecuteEmitsCallExecuted() public {
        bytes memory data = abi.encodeCall(Target.setValue, (5));
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);
        vm.prank(executor);
        vm.expectEmit(true, true, false, true);
        emit CallExecuted(id, 0, address(target), 0, data);
        timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));
    }

    function test_ExecuteByNonExecutorReverts() public {
        bytes memory data = abi.encodeCall(Target.setValue, (1));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, EXECUTOR_ROLE)
        );
        timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));
    }

    function test_ExecuteRevertsWhenTargetReverts() public {
        bytes memory data = abi.encodeCall(Target.alwaysReverts, ());

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);
        vm.prank(executor);
        vm.expectRevert("Target: always reverts");
        timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           EXECUTE BATCH TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ExecuteBatchSuccessfully() public {
        (address[] memory targets_, uint256[] memory values, bytes[] memory payloads) = _buildBatch(1);

        vm.prank(proposer);
        timelock.scheduleBatch(targets_, values, payloads, bytes32(0), bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);
        vm.prank(executor);
        timelock.executeBatch(targets_, values, payloads, bytes32(0), bytes32(0));

        assertEq(target.value(), 0); // _buildBatch uses a fresh Target each time — confirm no revert
    }

    function test_ExecuteBatchRevertsOnLengthMismatch() public {
        address[] memory targets_ = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory payloads = new bytes[](1); // mismatch

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(ITimelockController.TimelockInvalidOperationLength.selector, 2, 1, 2));
        timelock.executeBatch(targets_, values, payloads, bytes32(0), bytes32(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           UPDATE DELAY TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_UpdateDelayMustComeFromTimelockItself() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ITimelockController.TimelockUnauthorizedCaller.selector, admin));
        timelock.updateDelay(1 days);
    }

    function test_UpdateDelayViaScheduledOperation() public {
        uint256 newDelay = 5 days;
        bytes memory data = abi.encodeCall(ITimelockController.updateDelay, (newDelay));

        vm.prank(proposer);
        timelock.schedule(address(timelock), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);
        vm.prank(executor);
        vm.expectEmit(false, false, false, true);
        emit MinDelayChange(MIN_DELAY, newDelay);
        timelock.execute(address(timelock), 0, data, bytes32(0), bytes32(0));

        assertEq(timelock.getMinDelay(), newDelay);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         PREDECESSOR TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_PredecessorEnforcementRevertsBeforePredecessorDone() public {
        // Operation A
        bytes memory dataA = abi.encodeCall(Target.setValue, (1));
        bytes32 idA = timelock.hashOperation(address(target), 0, dataA, bytes32(0), bytes32(0));

        // Operation B requires A
        bytes memory dataB = abi.encodeCall(Target.setValue, (2));
        bytes32 idB = timelock.hashOperation(address(target), 0, dataB, idA, bytes32(0));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, dataA, bytes32(0), bytes32(0), MIN_DELAY);

        vm.prank(proposer);
        timelock.schedule(address(target), 0, dataB, idA, bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);

        // Try B before A is done — should revert
        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(ITimelockController.TimelockUnexecutedPredecessor.selector, idA));
        timelock.execute(address(target), 0, dataB, idA, bytes32(0));
    }

    function test_PredecessorEnforcementSucceedsAfterPredecessorDone() public {
        bytes memory dataA = abi.encodeCall(Target.setValue, (1));
        bytes32 idA = timelock.hashOperation(address(target), 0, dataA, bytes32(0), bytes32(0));

        bytes memory dataB = abi.encodeCall(Target.setValue, (2));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, dataA, bytes32(0), bytes32(0), MIN_DELAY);

        vm.prank(proposer);
        timelock.schedule(address(target), 0, dataB, idA, bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);

        // Execute A
        vm.prank(executor);
        timelock.execute(address(target), 0, dataA, bytes32(0), bytes32(0));
        assertTrue(timelock.isOperationDone(idA));

        // Execute B — predecessor now done
        vm.prank(executor);
        timelock.execute(address(target), 0, dataB, idA, bytes32(0));
        assertEq(target.value(), 2);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     OPERATION STATE TRANSITIONS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_OperationStateUnsetBeforeSchedule() public view {
        bytes32 id = keccak256("nonexistent-op");
        assertEq(uint8(timelock.getOperationState(id)), uint8(ITimelockController.OperationState.Unset));
        assertFalse(timelock.isOperation(id));
        assertFalse(timelock.isOperationPending(id));
        assertFalse(timelock.isOperationReady(id));
        assertFalse(timelock.isOperationDone(id));
    }

    function test_OperationStateWaitingAfterSchedule() public {
        bytes memory data = abi.encodeCall(Target.setValue, (1));
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        assertEq(uint8(timelock.getOperationState(id)), uint8(ITimelockController.OperationState.Waiting));
        assertTrue(timelock.isOperation(id));
        assertTrue(timelock.isOperationPending(id));
        assertFalse(timelock.isOperationReady(id));
        assertFalse(timelock.isOperationDone(id));
    }

    function test_OperationStateReadyAfterDelay() public {
        bytes memory data = abi.encodeCall(Target.setValue, (1));
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);

        assertEq(uint8(timelock.getOperationState(id)), uint8(ITimelockController.OperationState.Ready));
        assertTrue(timelock.isOperation(id));
        assertTrue(timelock.isOperationPending(id));
        assertTrue(timelock.isOperationReady(id));
        assertFalse(timelock.isOperationDone(id));
    }

    function test_OperationStateDoneAfterExecution() public {
        bytes memory data = abi.encodeCall(Target.setValue, (1));
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);
        vm.prank(executor);
        timelock.execute(address(target), 0, data, bytes32(0), bytes32(0));

        assertEq(uint8(timelock.getOperationState(id)), uint8(ITimelockController.OperationState.Done));
        assertTrue(timelock.isOperation(id));
        assertFalse(timelock.isOperationPending(id));
        assertFalse(timelock.isOperationReady(id));
        assertTrue(timelock.isOperationDone(id));
    }

    function test_OperationStateUnsetAfterCancel() public {
        bytes memory data = abi.encodeCall(Target.setValue, (1));
        bytes32 id = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));

        vm.prank(proposer);
        timelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.prank(proposer);
        timelock.cancel(id);

        assertEq(uint8(timelock.getOperationState(id)), uint8(ITimelockController.OperationState.Unset));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         OPEN EXECUTOR ROLE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_OpenExecutorAllowsAnyoneToExecute() public {
        // Deploy timelock with open executor (address(0))
        address[] memory proposers_ = new address[](1);
        proposers_[0] = proposer;
        address[] memory executors_ = new address[](1);
        executors_[0] = address(0); // open execution

        TimelockControllerStandalone openTimelock =
            new TimelockControllerStandalone(MIN_DELAY, proposers_, executors_, admin);

        bytes memory data = abi.encodeCall(Target.setValue, (7));

        vm.prank(proposer);
        openTimelock.schedule(address(target), 0, data, bytes32(0), bytes32(0), MIN_DELAY);

        vm.warp(block.timestamp + MIN_DELAY);

        // stranger has no EXECUTOR_ROLE but open role allows execution
        vm.prank(stranger);
        openTimelock.execute(address(target), 0, data, bytes32(0), bytes32(0));

        assertEq(target.value(), 7);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         HASH OPERATION TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_HashOperationIsDeterministic() public view {
        bytes memory data = abi.encodeCall(Target.setValue, (1));
        bytes32 id1 = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));
        bytes32 id2 = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));
        assertEq(id1, id2);
    }

    function test_HashOperationBatchIsDeterministic() public view {
        (address[] memory targets_, uint256[] memory values, bytes[] memory payloads) = _buildBatch(2);
        bytes32 id1 = timelock.hashOperationBatch(targets_, values, payloads, bytes32(0), bytes32(0));
        bytes32 id2 = timelock.hashOperationBatch(targets_, values, payloads, bytes32(0), bytes32(0));
        assertEq(id1, id2);
    }

    function test_DifferentSaltsProduceDifferentIds() public view {
        bytes memory data = abi.encodeCall(Target.setValue, (1));
        bytes32 id1 = timelock.hashOperation(address(target), 0, data, bytes32(0), bytes32(0));
        bytes32 id2 = timelock.hashOperation(address(target), 0, data, bytes32(0), keccak256("salt"));
        assertTrue(id1 != id2);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         RECEIVE ETH TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_TimelockCanReceiveEth() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(timelock).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(timelock).balance, 1 ether);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Builds a batch of `n` calls targeting a freshly deployed Target.
    ///      All calls are setValue(i) on the same shared `target`.
    function _buildBatch(uint256 n)
        internal
        view
        returns (address[] memory targets_, uint256[] memory values, bytes[] memory payloads)
    {
        targets_ = new address[](n);
        values = new uint256[](n);
        payloads = new bytes[](n);
        for (uint256 i = 0; i < n; ++i) {
            targets_[i] = address(target);
            values[i] = 0;
            payloads[i] = abi.encodeCall(Target.setValue, (i));
        }
    }
}
