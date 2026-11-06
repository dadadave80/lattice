// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployHSSAdapter} from "@lattice-script/base/oracles/DeployHSSAdapter.s.sol";
import {HederaProbeFacet, ProbeHedera} from "@lattice-script/config/hedera/ProbeHedera.s.sol";
import {MockHederaScheduleService} from "@lattice-test/mocks/hedera/MockHederaScheduleService.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IHSSAdapter} from "@lattice/interfaces/oracles/IHSSAdapter.sol";
import {HSS_SCHEDULER_ROLE, HSS_SYSTEM_CONTRACT} from "@lattice/oracles/hedera/HSSAdapterLib.sol";
import {Test} from "forge-std/Test.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

/// @dev Only the public relay transport and wall clock are replaced; the broadcast call uses a real diamond.
contract Probe6Harness is ProbeHedera {
    mapping(bytes32 => bytes) private _answers;
    uint256 public clock = 10_000;
    uint256 public reads;

    function answer(string memory method, string memory params, bytes memory value) external {
        _answers[keccak256(abi.encode(method, params))] = value;
    }

    function _rpc(string memory method, string memory params) internal override returns (bytes memory) {
        ++reads;
        ++clock;
        return _answers[keccak256(abi.encode(method, params))];
    }

    function _probe6WallClock() internal view override returns (uint256) {
        return clock;
    }
}

contract HederaProbe6Test is Test {
    address immutable ADMIN = address(this);
    bytes32 constant CORRELATION = keccak256("test probe6 attempt");
    address constant SCHEDULE = address(0x10001);
    address diamond;
    address hssFacet;
    address callbackFacet;
    Probe6Harness probe;
    MockHederaScheduleService nativeHss;

    function setUp() public {
        vm.chainId(296);
        vm.warp(123);
        vm.etch(HSS_SYSTEM_CONTRACT, address(new MockHederaScheduleService()).code);
        nativeHss = MockHederaScheduleService(HSS_SYSTEM_CONTRACT);
        nativeHss.configure(22, 22, 0);
        (FacetCut[] memory base, address init, bytes memory data) = new DeployHSSAdapter().buildCuts(ADMIN);
        FacetCut[] memory cuts = new FacetCut[](base.length + 1);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        callbackFacet = address(new HederaProbeFacet());
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = HederaProbeFacet.probeCallback.selector;
        cuts[base.length] = FacetCut(callbackFacet, FacetCutAction.Add, selectors);
        Lattice instance = new Lattice();
        instance.initialize(cuts, init, data);
        diamond = address(instance);
        hssFacet = IDiamondLoupe(diamond).facetAddress(IHSSAdapter.scheduleCall.selector);
        probe = new Probe6Harness();
        _code(diamond, diamond.code);
        _code(hssFacet, hssFacet.code);
        _code(callbackFacet, callbackFacet.code);
        _route(IHSSAdapter.scheduleCall.selector, hssFacet);
        _route(HederaProbeFacet.probeCallback.selector, callbackFacet);
        _role(ADMIN, abi.encode(true));
    }

    function _code(address target, bytes memory code) private {
        probe.answer("eth_getCode", string.concat('["', vm.toString(target), '","latest"]'), code);
    }

    function _read(address target, bytes memory data, bytes memory answer) private {
        probe.answer(
            "eth_call",
            string.concat('[{"to":"', vm.toString(target), '","data":"', vm.toString(data), '"},"latest"]'),
            answer
        );
    }

    function _route(bytes4 selector, address owner) private {
        _read(diamond, abi.encodeCall(IDiamondLoupe.facetAddress, (selector)), abi.encode(owner));
    }

    function _role(address account, bytes memory answer) private {
        _read(diamond, abi.encodeCall(IAccessControl.hasRole, (HSS_SCHEDULER_ROLE, account)), answer);
    }

    function _plan() private returns (uint256 expiry, bytes memory data) {
        return probe.planProbe6(diamond, ADMIN, hssFacet, callbackFacet, CORRELATION);
    }

    function test_PlanMakesNoTransactionAndUsesFreshWallClockAfterReads() public {
        vm.startStateDiffRecording();
        (uint256 expiry, bytes memory data) = _plan();
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        assertEq(expiry, probe.clock() + 600);
        assertGt(expiry, vm.getBlockTimestamp() + 600);
        assertEq(probe.reads(), 6);
        assertEq(
            data,
            abi.encodeCall(
                IHSSAdapter.scheduleCall,
                (diamond, expiry, 200_000, uint64(0), abi.encodeCall(HederaProbeFacet.probeCallback, (CORRELATION)))
            )
        );
        for (uint256 i; i < accesses.length; ++i) {
            assertTrue(accesses[i].account != diamond && accesses[i].account != HSS_SYSTEM_CONTRACT);
        }
        assertEq(nativeHss.payload(SCHEDULE).length, 0);
    }

    function test_ProbeQueuesExactlyOneZeroValueRootCallAndRawCorrelation() public {
        vm.recordLogs();
        vm.startStateDiffRecording();
        (uint256 expiry, bytes memory data) = probe.probe6(diamond, hssFacet, callbackFacet, CORRELATION);
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        uint256 rootCalls;
        uint256 nativeCalls;
        for (uint256 i; i < accesses.length; ++i) {
            // The test's entry call into the script precedes startBroadcast; only its downstream calls
            // belong to the planned transaction sequence.
            if (
                accesses[i].kind == VmSafe.AccountAccessKind.Call && accesses[i].accessor == ADMIN
                    && accesses[i].account != address(probe)
            ) {
                ++rootCalls;
                assertEq(accesses[i].account, diamond);
                assertEq(accesses[i].value, 0);
                assertEq(accesses[i].data, data);
            }
            if (accesses[i].account == HSS_SYSTEM_CONTRACT && accesses[i].kind == VmSafe.AccountAccessKind.Call) {
                ++nativeCalls;
            }
            assertTrue(accesses[i].kind != VmSafe.AccountAccessKind.Create, "no deployment in probe6");
        }
        assertEq(rootCalls, 1);
        assertEq(nativeCalls, 1);
        assertEq(expiry, probe.clock() + 600);
        assertEq(nativeHss.payload(SCHEDULE), abi.encodeCall(HederaProbeFacet.probeCallback, (CORRELATION)));
        assertEq(IHSSAdapter(diamond).scheduleOf(CORRELATION), address(0), "raw probe is not a tracked job");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, diamond);
        assertEq(logs[0].topics[0], keccak256("HSSCallScheduled(address,address,bytes32,uint256,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(SCHEDULE))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(diamond))));
        assertEq(logs[0].topics[3], bytes32(0));
        assertEq(logs[0].data, abi.encode(expiry, uint256(200_000)));

        // This mock intentionally ASSUMES payer-as-sender; it only proves exact event correlation locally.
        vm.recordLogs();
        (bool ok,) = nativeHss.fire(SCHEDULE);
        assertTrue(ok);
        logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, diamond);
        assertEq(logs[0].topics[0], keccak256("HederaProbeCallback(address,uint256,bytes32)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(diamond))));
        assertEq(logs[0].topics[2], CORRELATION);
        assertEq(logs[0].data, abi.encode(vm.getBlockTimestamp()));
    }

    function test_WrongChainRejected() public {
        vm.chainId(295);
        vm.expectRevert(abi.encodeWithSelector(ProbeHedera.Probe6WrongChain.selector, 295));
        _plan();
    }

    function test_ZeroCorrelationRejected() public {
        vm.expectRevert(ProbeHedera.Probe6InvalidCorrelation.selector);
        probe.planProbe6(diamond, ADMIN, hssFacet, callbackFacet, bytes32(0));
    }

    function test_ZeroTargetRejected() public {
        vm.expectRevert(abi.encodeWithSelector(ProbeHedera.Probe6MissingCode.selector, address(0)));
        probe.planProbe6(address(0), ADMIN, hssFacet, callbackFacet, CORRELATION);
    }

    function test_MissingLiveTargetRejected() public {
        _code(diamond, "");
        vm.expectRevert(abi.encodeWithSelector(ProbeHedera.Probe6MissingCode.selector, diamond));
        _plan();
    }

    function test_MissingCallbackCodeRejected() public {
        _code(callbackFacet, "");
        vm.expectRevert(abi.encodeWithSelector(ProbeHedera.Probe6MissingCode.selector, callbackFacet));
        _plan();
    }

    function test_MissingScheduleFacetCodeRejected() public {
        _code(hssFacet, "");
        vm.expectRevert(abi.encodeWithSelector(ProbeHedera.Probe6MissingCode.selector, hssFacet));
        _plan();
    }

    function test_ChangedScheduleRouteRejected() public {
        _route(IHSSAdapter.scheduleCall.selector, address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(
                ProbeHedera.Probe6RouteMismatch.selector, IHSSAdapter.scheduleCall.selector, hssFacet, address(0xBAD)
            )
        );
        _plan();
    }

    function test_ChangedCallbackRouteRejected() public {
        _route(HederaProbeFacet.probeCallback.selector, address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                ProbeHedera.Probe6RouteMismatch.selector,
                HederaProbeFacet.probeCallback.selector,
                callbackFacet,
                address(0)
            )
        );
        _plan();
    }

    function test_UnauthorizedSchedulerRejected() public {
        _role(ADMIN, abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(ProbeHedera.Probe6MissingSchedulerRole.selector, diamond, ADMIN));
        _plan();
    }

    function test_ProbeUsesActualCliSenderForRolePreflight() public {
        address other = address(0xB0B);
        _role(other, abi.encode(false));
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(ProbeHedera.Probe6MissingSchedulerRole.selector, diamond, other));
        probe.probe6(diamond, hssFacet, callbackFacet, CORRELATION);
        assertEq(nativeHss.payload(SCHEDULE).length, 0);
    }

    function test_MalformedRoleReadRejected() public {
        _role(ADMIN, hex"01");
        vm.expectRevert(ProbeHedera.Probe6MalformedRead.selector);
        _plan();
    }

    function test_MalformedAddressReadRejected() public {
        _read(diamond, abi.encodeCall(IDiamondLoupe.facetAddress, (IHSSAdapter.scheduleCall.selector)), new bytes(64));
        vm.expectRevert(ProbeHedera.Probe6MalformedRead.selector);
        _plan();
    }

    function test_NoncanonicalRoleReadRejected() public {
        _role(ADMIN, abi.encode(uint256(2)));
        vm.expectRevert(ProbeHedera.Probe6MalformedRead.selector);
        _plan();
    }

    function test_NoncanonicalAddressReadRejected() public {
        _read(
            diamond,
            abi.encodeCall(IDiamondLoupe.facetAddress, (IHSSAdapter.scheduleCall.selector)),
            abi.encode(1 << 200)
        );
        vm.expectRevert(ProbeHedera.Probe6MalformedRead.selector);
        _plan();
    }
}
