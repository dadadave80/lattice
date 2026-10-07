// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4;

/// @title IPrngSystemContract
/// @author Vendored minimal subset of hiero-ledger/hiero-contracts `contracts/prng/IPrngSystemContract.sol`
///         (https://github.com/hiero-ledger/hiero-contracts/blob/main/contracts/prng/IPrngSystemContract.sol),
///         commit 5ade6c8 (2026-09-09). Upstream license: Apache-2.0 (Hedera Hashgraph, LLC).
/// @notice ABI of the PRNG system contract at `0x0000000000000000000000000000000000000169` (HIP-351): returns
///         the 48-byte running hash of the previous transaction record truncated to 32 bytes. Not a `view` —
///         the call is recorded as a child transaction, so it must be reached with `call`, not `staticcall`.
interface IPrngSystemContract {
    function getPseudorandomSeed() external returns (bytes32 seed);
}
