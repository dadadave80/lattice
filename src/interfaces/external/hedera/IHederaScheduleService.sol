// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4;

/// @title IHederaScheduleService
/// @author Vendored minimal subset of hiero-ledger/hiero-contracts `contracts/schedule-service/{IHRC755,IHRC1215}.sol`
///         (https://github.com/hiero-ledger/hiero-contracts/tree/main/contracts/schedule-service), commit 5ade6c8
///         (2026-09-09). Upstream license: Apache-2.0 (Hedera Hashgraph, LLC).
/// @notice ABI of the Hedera Schedule Service system contract at `0x000000000000000000000000000000000000016b`:
///         HIP-755 (contract signatures on native scheduled transactions) and HIP-1215 (generalized scheduled
///         contract calls, live since consensus node v0.68 / mainnet 2026-01-15). Upstream splits these over
///         `IHRC755` and `IHRC1215`; they are merged here because both target the same address.
interface IHederaScheduleService {
    // ---- HIP-755: the calling contract signs a native scheduled transaction with its contract key ----
    function authorizeSchedule(address schedule) external returns (int64 responseCode);
    function signSchedule(address schedule, bytes memory signatureMap) external returns (int64 responseCode);

    // ---- HIP-1215: scheduled contract calls; the CALLING CONTRACT is the schedule payer ----
    function scheduleCall(address to, uint256 expirySecond, uint256 gasLimit, uint64 value, bytes memory callData)
        external
        returns (int64 responseCode, address scheduleAddress);
    function scheduleCallWithPayer(
        address to,
        address payer,
        uint256 expirySecond,
        uint256 gasLimit,
        uint64 value,
        bytes memory callData
    ) external returns (int64 responseCode, address scheduleAddress);
    function executeCallOnPayerSignature(
        address to,
        address payer,
        uint256 expirySecond,
        uint256 gasLimit,
        uint64 value,
        bytes memory callData
    ) external returns (int64 responseCode, address scheduleAddress);
    function deleteSchedule(address scheduleAddress) external returns (int64 responseCode);
    function hasScheduleCapacity(uint256 expirySecond, uint256 gasLimit) external view returns (bool hasCapacity);
}
