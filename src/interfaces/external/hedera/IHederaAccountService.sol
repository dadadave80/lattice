// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4;

/// @title IHederaAccountService
/// @author Vendored minimal subset of hiero-ledger/hiero-contracts `contracts/account-service/IHederaAccountService.sol`
///         (https://github.com/hiero-ledger/hiero-contracts/blob/main/contracts/account-service/IHederaAccountService.sol),
///         commit 5ade6c8 (2026-09-09). Upstream license: Apache-2.0 (Hedera Hashgraph, LLC).
/// @notice ABI of the Hedera Account Service system contract at `0x000000000000000000000000000000000000016a`
///         (HIP-632). Both functions are view-classified by the network and callable via `staticcall`.
interface IHederaAccountService {
    /// @notice Verifies `signature` over the 32-byte `messageHash` against `account`'s SIMPLE key: a 65-byte blob
    ///         is checked as ECDSA-secp256k1 (ecrecover), a 64-byte blob as ED25519. Reverts (rather than
    ///         returning false) on malformed input, key lists / threshold keys, or insufficient gas.
    function isAuthorizedRaw(address account, bytes memory messageHash, bytes memory signature)
        external
        returns (bool authorized);

    /// @notice Verifies a protobuf `SignatureMap` over the raw `message` against `account`'s full key structure
    ///         (ED25519, ECDSA, KeyList, ThresholdKey). Failures are returned as response codes.
    function isAuthorized(address account, bytes memory message, bytes memory signature)
        external
        returns (int64 responseCode, bool authorized);
}
