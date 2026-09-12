// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {HederaResponseCodes} from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import {IHederaScheduleService} from "@lattice/interfaces/external/hedera/IHederaScheduleService.sol";
import {IHSSAdapter} from "@lattice/interfaces/oracles/IHSSAdapter.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.HSSAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant HSS_ADAPTER_STORAGE_SLOT = 0x12fa09b7b2cb13ace416911567e16cefd04261b5db45857ec33ecae7c1298700;

/// @dev 0xd07095cf is `type(IHSSAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xd07095cf), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IHSSADAPTER_SLOT = 0x336d3eab18c157b0aa1696b6a9cef1943b53e0b1cdacf2490de1d33245c45247;

/// @dev Role allowed to schedule, delete and authorize schedules on the diamond's behalf.
bytes32 constant HSS_SCHEDULER_ROLE = keccak256("HSS_SCHEDULER_ROLE");

/// @dev The Hedera Schedule Service system contract (HIP-755 / HIP-1215). No bytecode; never `delegatecall` it.
address constant HSS_SYSTEM_CONTRACT = 0x000000000000000000000000000000000000016B;

/// @notice ERC-7201 namespaced storage for HSSAdapter.
/// @custom:storage-location erc7201:lattice.storage.HSSAdapter
struct HSSAdapterStorage {
    /// @notice Live schedule address per self-call job. APPEND-ONLY.
    mapping(bytes32 jobId => address scheduleAddress) _schedules;
}

/// @title HSSAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Logic + ERC-7201 storage for the diamond's use of the Hedera Schedule Service.
/// @dev `scheduleCall` makes the CALLING CONTRACT the schedule payer and the schedule's admin key, so the
///      diamond funds execution from its own HBAR and can delete what it scheduled. When the network fires the
///      call, the diamond is the sender — a self-scheduled callback therefore sees `msg.sender == address(this)`,
///      which {checkScheduledSelfCall} uses as its guard.
library HSSAdapterLib {
    function hssAdapterStorage() internal pure returns (HSSAdapterStorage storage $) {
        assembly {
            $.slot := HSS_ADAPTER_STORAGE_SLOT
        }
    }

    function __HSSAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IHSSADAPTER_SLOT, true)
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

    /// @notice Reverts unless the current frame is the diamond executing its own scheduled call.
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
        scheduleAddress = _schedule(address(this), expirySecond, gasLimit, 0, data);
        $._schedules[jobId] = scheduleAddress;
        emit IHSSAdapter.HSSCallScheduled(scheduleAddress, address(this), jobId, expirySecond, gasLimit);
    }

    function completeSelfCall(bytes32 jobId) internal {
        checkScheduledSelfCall();
        delete hssAdapterStorage()._schedules[jobId];
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

    function _schedule(address to, uint256 expirySecond, uint256 gasLimit, uint64 value, bytes calldata data)
        private
        returns (address scheduleAddress)
    {
        if (expirySecond <= block.timestamp) revert IHSSAdapter.HSSInvalidExpiry(expirySecond);
        (bool ok, bytes memory ret) = HSS_SYSTEM_CONTRACT.call(
            abi.encodeCall(IHederaScheduleService.scheduleCall, (to, expirySecond, gasLimit, value, data))
        );
        int64 code = HederaResponseCodes.UNKNOWN;
        if (ok) (code, scheduleAddress) = abi.decode(ret, (int64, address));
        if (code == HederaResponseCodes.SCHEDULE_EXPIRY_IS_BUSY) revert IHSSAdapter.HSSExpiryBusy(expirySecond, gasLimit);
        if (code != HederaResponseCodes.SUCCESS) {
            revert IHSSAdapter.HSSCallFailed(IHederaScheduleService.scheduleCall.selector, code);
        }
    }

    function _callForCode(bytes memory data) private returns (int64 code) {
        (bool ok, bytes memory ret) = HSS_SYSTEM_CONTRACT.call(data);
        code = ok ? abi.decode(ret, (int64)) : HederaResponseCodes.UNKNOWN;
    }
}
