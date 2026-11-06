// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {HederaResponseCodes} from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import {IHederaScheduleService} from "@lattice/interfaces/external/hedera/IHederaScheduleService.sol";
import {IHSSAdapter} from "@lattice/interfaces/oracles/IHSSAdapter.sol";
import {IHSSAdapterRecovery} from "@lattice/interfaces/oracles/IHSSAdapterRecovery.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.HSSAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant HSS_ADAPTER_STORAGE_SLOT = 0x12fa09b7b2cb13ace416911567e16cefd04261b5db45857ec33ecae7c1298700;

/// @dev 0xd07095cf is `type(IHSSAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xd07095cf), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IHSSADAPTER_SLOT = 0x336d3eab18c157b0aa1696b6a9cef1943b53e0b1cdacf2490de1d33245c45247;

/// @dev 0x4d10dd54 is `type(IHSSAdapterRecovery).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x4d10dd54), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IHSSADAPTERRECOVERY_SLOT =
    0xd8059154e8e96e6eecaf07fe11ba32eaf97db00d355f926132173527e14d213a;

/// @dev Role allowed to schedule, delete and authorize schedules on the diamond's behalf.
bytes32 constant HSS_SCHEDULER_ROLE = keccak256("HSS_SCHEDULER_ROLE");

/// @dev The Hedera Schedule Service system contract (HIP-755 / HIP-1215). No bytecode; never `delegatecall` it.
address constant HSS_SYSTEM_CONTRACT = 0x000000000000000000000000000000000000016B;

/// @notice ERC-7201 namespaced storage for HSSAdapter.
/// @custom:storage-location erc7201:lattice.storage.HSSAdapter
struct HSSAdapterStorage {
    /// @notice Live schedule address per self-call job. APPEND-ONLY.
    mapping(bytes32 jobId => address scheduleAddress) _schedules;
    /// @notice Monotonic booking/cancellation nonce. APPEND-ONLY; never reset on completion.
    mapping(bytes32 jobId => uint256 generation) _generations;
    bytes32 _activeJobId;
    uint256 _activeGeneration;
}

/// @title HSSAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Logic + ERC-7201 storage for the diamond's use of the Hedera Schedule Service.
/// @dev `scheduleCall` makes the CALLING CONTRACT the schedule payer and the schedule's admin key, so the
///      diamond funds execution from its own HBAR and can delete what it scheduled. When the network fires the
///      call, the design assumes the diamond is the sender; live callback identity remains unverified.
///      Wrapped callbacks also authenticate their booked generation before executing any payload.
library HSSAdapterLib {
    function hssAdapterStorage() internal pure returns (HSSAdapterStorage storage $) {
        assembly {
            $.slot := HSS_ADAPTER_STORAGE_SLOT
        }
    }

    function __HSSAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        _checkRecoveryInstalled();
        registerInterfaces();
    }

    function registerInterfaces() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IHSSADAPTER_SLOT, true)
            sstore(ERC165_MAP_IHSSADAPTERRECOVERY_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function hasScheduleCapacity(uint256 expirySecond, uint256 gasLimit) internal view returns (bool) {
        return IHederaScheduleService(HSS_SYSTEM_CONTRACT).hasScheduleCapacity(expirySecond, gasLimit);
    }

    function scheduleOf(bytes32 jobId) internal view returns (address) {
        return hssAdapterStorage()._schedules[jobId];
    }

    /// @notice Checks self-call authority; composition must not expose an unrestricted self-call executor.
    function checkScheduledSelfCall() internal view {
        if (msg.sender != address(this)) revert IHSSAdapter.HSSNotScheduledSelfCall();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 SCHEDULING
    //////////////////////////////////////////////////////////////////////////*//

    function scheduleCall(address to, uint256 expirySecond, uint256 gasLimit, uint64 value, bytes calldata data)
        internal
        returns (address scheduleAddress)
    {
        AccessControlLib.checkRole(HSS_SCHEDULER_ROLE);
        scheduleAddress = _schedule(to, expirySecond, gasLimit, value, data);
        emit IHSSAdapter.HSSCallScheduled(scheduleAddress, to, bytes32(0), expirySecond, gasLimit);
    }

    function scheduleSelfCall(bytes32 jobId, uint256 expirySecond, uint256 gasLimit, bytes calldata data)
        internal
        returns (address scheduleAddress)
    {
        AccessControlLib.checkRole(HSS_SCHEDULER_ROLE);
        HSSAdapterStorage storage $ = hssAdapterStorage();
        if ($._schedules[jobId] != address(0)) revert IHSSAdapter.HSSJobAlreadyScheduled(jobId, $._schedules[jobId]);
        _checkRecoveryInstalled();
        uint256 generation = ++$._generations[jobId];
        scheduleAddress = _schedule(
            address(this),
            expirySecond,
            gasLimit,
            0,
            abi.encodeCall(IHSSAdapterRecovery.executeSelfCall, (jobId, generation, data))
        );
        $._schedules[jobId] = scheduleAddress;
        emit IHSSAdapter.HSSCallScheduled(scheduleAddress, address(this), jobId, expirySecond, gasLimit);
        emit IHSSAdapterRecovery.HSSSelfCallGeneration(jobId, generation, scheduleAddress);
    }

    /// @dev An unbound legacy/raw self-call cannot complete a replacement job.
    function completeSelfCall(bytes32 jobId) internal {
        checkScheduledSelfCall();
        HSSAdapterStorage storage $ = hssAdapterStorage();
        if (
            $._activeGeneration == 0 || $._activeJobId != jobId || $._activeGeneration != $._generations[jobId]
                || $._schedules[jobId] == address(0)
        ) revert IHSSAdapterRecovery.HSSInvalidExecutionContext(jobId);
        delete $._schedules[jobId];
    }

    function executeSelfCall(bytes32 jobId, uint256 generation, bytes calldata data) internal {
        checkScheduledSelfCall();
        HSSAdapterStorage storage $ = hssAdapterStorage();
        if ($._activeGeneration != 0) revert IHSSAdapterRecovery.HSSSelfCallAlreadyExecuting();
        if (generation == 0 || generation != $._generations[jobId] || $._schedules[jobId] == address(0)) {
            revert IHSSAdapterRecovery.HSSStaleSelfCall(jobId, generation);
        }
        $._activeJobId = jobId;
        $._activeGeneration = generation;
        (bool ok, bytes memory result) = address(this).call(data);
        if (!ok) {
            assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        }
        delete $._activeJobId;
        delete $._activeGeneration;
    }

    function cancelSelfCall(bytes32 jobId) internal returns (bool deleted) {
        AccessControlLib.checkRole(HSS_SCHEDULER_ROLE);
        HSSAdapterStorage storage $ = hssAdapterStorage();
        address schedule = $._schedules[jobId];
        if (schedule == address(0)) revert IHSSAdapterRecovery.HSSNoScheduledJob(jobId);
        uint256 generation = $._generations[jobId]++;
        delete $._schedules[jobId];
        bytes memory input = abi.encodeCall(IHederaScheduleService.deleteSchedule, (schedule));
        uint256 successCode = uint64(HederaResponseCodes.SUCCESS);
        // Bound native work/return data and reserve gas for the local cancellation event and return.
        assembly ("memory-safe") {
            let output := mload(0x40)
            mstore(output, 0)
            let callGas := 100000
            if lt(gas(), 110000) { callGas := 0 }
            let ok := call(callGas, HSS_SYSTEM_CONTRACT, 0, add(input, 32), mload(input), output, 32)
            deleted := and(and(ok, gt(returndatasize(), 31)), eq(mload(output), successCode))
        }
        emit IHSSAdapterRecovery.HSSSelfCallCancelled(jobId, schedule, generation, deleted);
    }

    function deleteSchedule(address scheduleAddress) internal {
        AccessControlLib.checkRole(HSS_SCHEDULER_ROLE);
        int64 code = _callForCode(abi.encodeCall(IHederaScheduleService.deleteSchedule, (scheduleAddress)));
        if (code != HederaResponseCodes.SUCCESS) {
            revert IHSSAdapter.HSSCallFailed(IHederaScheduleService.deleteSchedule.selector, code);
        }
        emit IHSSAdapter.HSSScheduleDeleted(scheduleAddress);
    }

    function authorizeSchedule(address scheduleAddress) internal {
        AccessControlLib.checkRole(HSS_SCHEDULER_ROLE);
        int64 code = _callForCode(abi.encodeCall(IHederaScheduleService.authorizeSchedule, (scheduleAddress)));
        if (code != HederaResponseCodes.SUCCESS) {
            revert IHSSAdapter.HSSCallFailed(IHederaScheduleService.authorizeSchedule.selector, code);
        }
        emit IHSSAdapter.HSSScheduleAuthorized(scheduleAddress);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 INTERNALS
    //////////////////////////////////////////////////////////////////////////*//

    function _checkRecoveryInstalled() private view {
        if (
            DiamondLib.selectorToFacet(DiamondLib.diamondStorage(), IHSSAdapterRecovery.executeSelfCall.selector)
                    == address(0)
                || DiamondLib.selectorToFacet(DiamondLib.diamondStorage(), IHSSAdapterRecovery.cancelSelfCall.selector)
                    == address(0)
        ) {
            revert IHSSAdapterRecovery.HSSRecoveryNotInstalled();
        }
    }

    function _schedule(address to, uint256 expirySecond, uint256 gasLimit, uint64 value, bytes memory data)
        private
        returns (address scheduleAddress)
    {
        if (expirySecond <= block.timestamp) revert IHSSAdapter.HSSInvalidExpiry(expirySecond);
        (bool ok, bytes memory ret) = HSS_SYSTEM_CONTRACT.call(
            abi.encodeCall(IHederaScheduleService.scheduleCall, (to, expirySecond, gasLimit, value, data))
        );
        int64 code = HederaResponseCodes.UNKNOWN;
        if (ok && ret.length >= 64) (code, scheduleAddress) = abi.decode(ret, (int64, address));
        if (code == HederaResponseCodes.SUCCESS && scheduleAddress == address(0)) code = HederaResponseCodes.UNKNOWN;
        if (code == HederaResponseCodes.SCHEDULE_EXPIRY_IS_BUSY) {
            revert IHSSAdapter.HSSExpiryBusy(expirySecond, gasLimit);
        }
        if (code != HederaResponseCodes.SUCCESS) {
            revert IHSSAdapter.HSSCallFailed(IHederaScheduleService.scheduleCall.selector, code);
        }
    }

    function _callForCode(bytes memory data) private returns (int64 code) {
        (bool ok, bytes memory ret) = HSS_SYSTEM_CONTRACT.call(data);
        code = ok ? abi.decode(ret, (int64)) : HederaResponseCodes.UNKNOWN;
    }
}
