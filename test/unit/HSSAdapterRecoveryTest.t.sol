// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IDiamondCut} from "@diamond/interfaces/IDiamondCut.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployHSSAdapter} from "@lattice-script/base/oracles/DeployHSSAdapter.s.sol";
import {MockHederaScheduleService} from "@lattice-test/mocks/hedera/MockHederaScheduleService.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IHSSAdapter} from "@lattice/interfaces/oracles/IHSSAdapter.sol";
import {IHSSAdapterRecovery} from "@lattice/interfaces/oracles/IHSSAdapterRecovery.sol";
import {HSSAdapter} from "@lattice/oracles/hedera/HSSAdapter.sol";
import {
    HSSAdapterLib,
    HSS_ADAPTER_STORAGE_SLOT,
    HSS_SCHEDULER_ROLE,
    HSS_SYSTEM_CONTRACT
} from "@lattice/oracles/hedera/HSSAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

contract HSSRecoveryCallback {
    uint256 public calls;

    function callback(bytes32 job) external {
        IHSSAdapter(address(this)).completeSelfCall(job);
        ++calls;
    }

    function noComplete(bytes32) external {
        ++calls;
    }

    function revertCallback(bytes32 job) external {
        IHSSAdapter(address(this)).completeSelfCall(job);
        ++calls;
        revert("callback failed");
    }

    function wrongJob(bytes32 job) external {
        IHSSAdapter(address(this)).completeSelfCall(job);
    }

    function doubleComplete(bytes32 job) external {
        IHSSAdapter(address(this)).completeSelfCall(job);
        IHSSAdapter(address(this)).completeSelfCall(job);
    }

    function recur(bytes32 job, uint256 expiry, bool fail) external {
        IHSSAdapter(address(this)).completeSelfCall(job);
        IHSSAdapter(address(this)).scheduleSelfCall(job, expiry, 1_000_000, abi.encodeCall(this.callback, (job)));
        ++calls;
        require(!fail, "recurrence failed");
    }

    function nested(bytes32 job, uint256 generation) external {
        IHSSAdapterRecovery(address(this)).executeSelfCall(job, generation, abi.encodeCall(this.callback, (job)));
    }
}

contract HSSAdapterRecoveryTest is Test {
    bytes32 constant JOB = keccak256("job");
    address constant ADMIN = address(0xA11CE);
    address diamond;
    IHSSAdapter hss;
    IHSSAdapterRecovery recovery;
    MockHederaScheduleService nativeHss;

    function setUp() public {
        vm.etch(HSS_SYSTEM_CONTRACT, address(new MockHederaScheduleService()).code);
        nativeHss = MockHederaScheduleService(HSS_SYSTEM_CONTRACT);
        nativeHss.configure(22, 22, 0);
        (FacetCut[] memory base, address init, bytes memory data) = new DeployHSSAdapter().buildCuts(ADMIN);
        FacetCut[] memory cuts = new FacetCut[](base.length + 1);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = HSSRecoveryCallback.callback.selector;
        selectors[1] = bytes4(keccak256("calls()"));
        selectors[2] = HSSRecoveryCallback.noComplete.selector;
        selectors[3] = HSSRecoveryCallback.revertCallback.selector;
        selectors[4] = HSSRecoveryCallback.wrongJob.selector;
        selectors[5] = HSSRecoveryCallback.doubleComplete.selector;
        selectors[6] = HSSRecoveryCallback.recur.selector;
        selectors[7] = HSSRecoveryCallback.nested.selector;
        cuts[base.length] = FacetCut(address(new HSSRecoveryCallback()), FacetCutAction.Add, selectors);
        Lattice d = new Lattice();
        d.initialize(cuts, init, data);
        diamond = address(d);
        hss = IHSSAdapter(diamond);
        recovery = IHSSAdapterRecovery(diamond);
    }

    function _schedule() internal returns (address schedule) {
        return _book(JOB, abi.encodeCall(HSSRecoveryCallback.callback, (JOB)));
    }

    function _book(bytes32 job, bytes memory data) internal returns (address schedule) {
        vm.prank(ADMIN);
        return hss.scheduleSelfCall(job, vm.getBlockTimestamp() + 600, 1_000_000, data);
    }

    function _cancel() internal returns (bool) {
        vm.prank(ADMIN);
        return recovery.cancelSelfCall(JOB);
    }

    function _generation(address schedule) internal view returns (uint256 generation) {
        bytes memory data = nativeHss.payload(schedule);
        assertEq(bytes4(data), IHSSAdapterRecovery.executeSelfCall.selector);
        assembly ("memory-safe") { generation := mload(add(data, 68)) }
    }

    function _assertIdle() internal view {
        assertEq(vm.load(diamond, bytes32(uint256(HSS_ADAPTER_STORAGE_SLOT) + 2)), bytes32(0));
        assertEq(vm.load(diamond, bytes32(uint256(HSS_ADAPTER_STORAGE_SLOT) + 3)), bytes32(0));
    }

    function _allowRecurrence() internal {
        vm.prank(ADMIN);
        AccessControl(diamond).grantRole(HSS_SCHEDULER_ROLE, diamond);
    }

    function test_DeletedJobCanBeRecoveredAndReplaced() public {
        address old = _schedule();
        vm.prank(ADMIN);
        hss.deleteSchedule(old);
        assertEq(hss.scheduleOf(JOB), old, "native delete does not free the local job");
        assertTrue(_cancel());
        assertEq(hss.scheduleOf(JOB), address(0));
        assertTrue(_schedule() != old, "replacement must be a new native schedule");
    }

    function test_ExpiredUnfiredJobCanBeReplaced() public {
        address old = _schedule();
        vm.warp(vm.getBlockTimestamp() + 601);
        _cancel();
        assertTrue(_schedule() != old);
    }

    function test_CancelUnauthorized() public {
        _schedule();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), HSS_SCHEDULER_ROLE
            )
        );
        recovery.cancelSelfCall(JOB);
    }

    function test_CancelUnknownJob() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IHSSAdapterRecovery.HSSNoScheduledJob.selector, JOB));
        recovery.cancelSelfCall(JOB);
    }

    function test_CompleteNonSelfReverts() public {
        _schedule();
        vm.expectRevert(IHSSAdapter.HSSNotScheduledSelfCall.selector);
        hss.completeSelfCall(JOB);
    }

    function test_EnvelopeExternalCallerCannotFireEarly() public {
        address schedule = _schedule();
        uint256 generation = _generation(schedule);
        vm.expectRevert(IHSSAdapter.HSSNotScheduledSelfCall.selector);
        recovery.executeSelfCall(JOB, generation, abi.encodeCall(HSSRecoveryCallback.callback, (JOB)));
        assertEq(HSSRecoveryCallback(diamond).calls(), 0);
        assertEq(hss.scheduleOf(JOB), schedule);
    }

    function test_RawSelfCompletionCannotClearReplacement() public {
        _schedule();
        _cancel();
        address replacement = _schedule();
        vm.prank(diamond);
        vm.expectRevert(abi.encodeWithSelector(IHSSAdapterRecovery.HSSInvalidExecutionContext.selector, JOB));
        hss.completeSelfCall(JOB);
        assertEq(hss.scheduleOf(JOB), replacement);
    }

    function test_StaleEnvelopeCannotExecuteOrClearReplacement() public {
        address old = _schedule();
        _cancel();
        address replacement = _schedule();
        (bool ok, bytes memory result) = nativeHss.fire(old);
        assertFalse(ok);
        assertEq(result, abi.encodeWithSelector(IHSSAdapterRecovery.HSSStaleSelfCall.selector, JOB, _generation(old)));
        assertEq(hss.scheduleOf(JOB), replacement);
        assertEq(HSSRecoveryCallback(diamond).calls(), 0);
    }

    function test_SuccessfulFireCompletesOnce() public {
        address schedule = _schedule();
        (bool ok,) = nativeHss.fire(schedule);
        assertTrue(ok);
        assertEq(hss.scheduleOf(JOB), address(0));
        assertEq(HSSRecoveryCallback(diamond).calls(), 1);
        (ok,) = nativeHss.fire(schedule);
        assertFalse(ok, "completed envelope replayed");
        _assertIdle();
    }

    function test_FailedCallbackRollsBackCompletionAndCanCancel() public {
        address schedule = _book(JOB, abi.encodeCall(HSSRecoveryCallback.revertCallback, (JOB)));
        (bool ok, bytes memory result) = nativeHss.fire(schedule);
        assertFalse(ok);
        assertEq(result, abi.encodeWithSignature("Error(string)", "callback failed"));
        assertEq(hss.scheduleOf(JOB), schedule);
        assertEq(HSSRecoveryCallback(diamond).calls(), 0);
        _assertIdle();
        _cancel();
        assertTrue(_schedule() != schedule);
    }

    function test_CompleteThenRecurPreservesNewSchedule() public {
        _allowRecurrence();
        address old = _book(JOB, abi.encodeCall(HSSRecoveryCallback.recur, (JOB, vm.getBlockTimestamp() + 1200, false)));
        (bool ok,) = nativeHss.fire(old);
        assertTrue(ok);
        address replacement = hss.scheduleOf(JOB);
        assertTrue(replacement != address(0) && replacement != old);
        assertGt(_generation(replacement), _generation(old));
        _assertIdle();
        (ok,) = nativeHss.fire(replacement);
        assertTrue(ok);
        assertEq(hss.scheduleOf(JOB), address(0));
    }

    function test_FailedRecurrenceRollsBackNewGeneration() public {
        _allowRecurrence();
        address old = _book(JOB, abi.encodeCall(HSSRecoveryCallback.recur, (JOB, vm.getBlockTimestamp() + 1200, true)));
        (bool ok,) = nativeHss.fire(old);
        assertFalse(ok);
        assertEq(hss.scheduleOf(JOB), old);
        assertEq(HSSRecoveryCallback(diamond).calls(), 0);
        _assertIdle();
        _cancel();
        assertEq(_generation(_schedule()), _generation(old) + 2);
    }

    function test_DoubleCompleteRevertsAtomically() public {
        address schedule = _book(JOB, abi.encodeCall(HSSRecoveryCallback.doubleComplete, (JOB)));
        (bool ok,) = nativeHss.fire(schedule);
        assertFalse(ok);
        assertEq(hss.scheduleOf(JOB), schedule);
    }

    function test_WrongJobContextCannotClearAnotherJob() public {
        bytes32 other = keccak256("other");
        address otherSchedule = _book(other, abi.encodeCall(HSSRecoveryCallback.callback, (other)));
        address schedule = _book(JOB, abi.encodeCall(HSSRecoveryCallback.wrongJob, (other)));
        (bool ok,) = nativeHss.fire(schedule);
        assertFalse(ok);
        assertEq(hss.scheduleOf(other), otherSchedule);
        assertEq(hss.scheduleOf(JOB), schedule);
    }

    function test_NestedEnvelopeRejected() public {
        address schedule = _book(JOB, abi.encodeCall(HSSRecoveryCallback.nested, (JOB, 1)));
        (bool ok, bytes memory result) = nativeHss.fire(schedule);
        assertFalse(ok);
        assertEq(result, abi.encodeWithSelector(IHSSAdapterRecovery.HSSSelfCallAlreadyExecuting.selector));
        assertEq(hss.scheduleOf(JOB), schedule);
        _assertIdle();
    }

    function test_CallbackWithoutCompletionCanBeRecovered() public {
        address schedule = _book(JOB, abi.encodeCall(HSSRecoveryCallback.noComplete, (JOB)));
        (bool ok,) = nativeHss.fire(schedule);
        assertTrue(ok);
        assertEq(hss.scheduleOf(JOB), schedule);
        _assertIdle();
        _cancel();
        assertTrue(_schedule() != schedule);
    }

    function testFuzz_CancelIgnoresNativeDeleteFailure(uint8 mode) public {
        mode = uint8(bound(mode, 0, 5));
        address old = _schedule();
        nativeHss.configure(22, 21, mode);
        bool deleted = _cancel();
        assertEq(deleted, mode == 4);
        assertEq(hss.scheduleOf(JOB), address(0));
        assertTrue(_schedule() != old);
    }

    function test_LegacyJobCanBeCancelledButNotCompletedRaw() public {
        bytes32 slot = keccak256(abi.encode(JOB, HSS_ADAPTER_STORAGE_SLOT));
        vm.store(diamond, slot, bytes32(uint256(uint160(address(0x1234)))));
        vm.prank(diamond);
        vm.expectRevert(abi.encodeWithSelector(IHSSAdapterRecovery.HSSInvalidExecutionContext.selector, JOB));
        hss.completeSelfCall(JOB);
        // Native cannot identify this synthetic pre-upgrade job; local cancellation must still work.
        assertFalse(_cancel());
        assertEq(_generation(_schedule()), 2);
    }

    function testFuzz_SchedulingFailureRollsBackGeneration(int64 code) public {
        code = int64(bound(int256(code), -3, 23));
        vm.assume(code != 22);
        nativeHss.configure(code, 22, 0);
        vm.prank(ADMIN);
        vm.expectRevert();
        hss.scheduleSelfCall(
            JOB, vm.getBlockTimestamp() + 600, 1_000_000, abi.encodeCall(HSSRecoveryCallback.callback, (JOB))
        );
        assertEq(hss.scheduleOf(JOB), address(0));
        nativeHss.configure(22, 22, 0);
        assertEq(_generation(_schedule()), 1);
    }

    function test_InvalidExpiryRollsBackGeneration() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IHSSAdapter.HSSInvalidExpiry.selector, vm.getBlockTimestamp()));
        hss.scheduleSelfCall(JOB, vm.getBlockTimestamp(), 1_000_000, hex"");
        assertEq(_generation(_schedule()), 1);
    }

    function test_MissingDispatcherRejectsBooking() public {
        FacetCut[] memory cuts = new FacetCut[](1);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IHSSAdapterRecovery.executeSelfCall.selector;
        cuts[0] = FacetCut(address(0), FacetCutAction.Remove, selectors);
        vm.prank(ADMIN);
        IDiamondCut(diamond).diamondCut(cuts, address(0), hex"");
        vm.prank(ADMIN);
        vm.expectRevert(IHSSAdapterRecovery.HSSRecoveryNotInstalled.selector);
        hss.scheduleSelfCall(JOB, vm.getBlockTimestamp() + 600, 1_000_000, hex"");
    }

    function test_FrozenInterfaceAndSelectorSetPreserved() public {
        assertEq(type(IHSSAdapter).interfaceId, bytes4(0xd07095cf));
        assertEq(new HSSAdapter().exportSelectors(), hex"f06379611735e9e072d42394dfb4a9996f5bfde8ec2a7610193704bb");
        assertEq(type(IHSSAdapterRecovery).interfaceId, bytes4(0x4d10dd54));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IHSSAdapter).interfaceId));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IHSSAdapterRecovery).interfaceId));
    }

    function test_GenericScheduleCallKeepsRawPayload() public {
        vm.prank(ADMIN);
        address schedule = hss.scheduleCall(diamond, vm.getBlockTimestamp() + 600, 1_000_000, 0, hex"12345678");
        assertEq(nativeHss.payload(schedule), hex"12345678");
        assertEq(hss.scheduleOf(JOB), address(0));
    }

    function test_ActiveJobCannotBeOverwritten() public {
        address old = _schedule();
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IHSSAdapter.HSSJobAlreadyScheduled.selector, JOB, old));
        hss.scheduleSelfCall(JOB, vm.getBlockTimestamp() + 600, 1_000_000, hex"");
        assertEq(hss.scheduleOf(JOB), old);
    }

    function test_BusyExpiryRollsBackBooking() public {
        nativeHss.configure(370, 22, 0);
        uint256 expiry = vm.getBlockTimestamp() + 600;
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IHSSAdapter.HSSExpiryBusy.selector, expiry, 1_000_000));
        hss.scheduleSelfCall(JOB, expiry, 1_000_000, hex"");
        nativeHss.configure(22, 22, 0);
        assertEq(_generation(_schedule()), 1);
    }

    function test_LowGasCancellationStillClearsLocally() public {
        _schedule();
        vm.prank(ADMIN);
        (bool ok, bytes memory result) =
            diamond.call{gas: 60_000}(abi.encodeCall(IHSSAdapterRecovery.cancelSelfCall, (JOB)));
        assertTrue(ok);
        assertFalse(abi.decode(result, (bool)), "low gas must preserve a cancellation reserve");
        assertEq(hss.scheduleOf(JOB), address(0));
    }

    function test_LegacyRawPayloadMayRunButCannotClearReplacement() public {
        vm.prank(ADMIN);
        address legacy = hss.scheduleCall(
            diamond, vm.getBlockTimestamp() + 600, 1_000_000, 0, abi.encodeCall(HSSRecoveryCallback.noComplete, (JOB))
        );
        vm.store(diamond, keccak256(abi.encode(JOB, HSS_ADAPTER_STORAGE_SLOT)), bytes32(uint256(uint160(legacy))));
        nativeHss.configure(22, 21, 0);
        assertFalse(_cancel());
        address replacement = _schedule();
        (bool ok,) = nativeHss.fire(legacy);
        assertTrue(ok, "local cancellation cannot veto an already scheduled raw payload");
        assertEq(HSSRecoveryCallback(diamond).calls(), 1);
        assertEq(hss.scheduleOf(JOB), replacement);
    }

    function test_ZeroJobIdHasIndependentExecutionContext() public {
        address schedule = _book(bytes32(0), abi.encodeCall(HSSRecoveryCallback.callback, (bytes32(0))));
        (bool ok,) = nativeHss.fire(schedule);
        assertTrue(ok);
        assertEq(hss.scheduleOf(bytes32(0)), address(0));
        _assertIdle();
    }
}
