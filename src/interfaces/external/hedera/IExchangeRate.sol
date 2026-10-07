// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4;

/// @title IExchangeRate
/// @author Vendored minimal subset of hiero-ledger/hiero-contracts `contracts/exchange-rate/IExchangeRate.sol`
///         (https://github.com/hiero-ledger/hiero-contracts/blob/main/contracts/exchange-rate/IExchangeRate.sol),
///         commit 5ade6c8 (2026-09-09). Upstream license: Apache-2.0 (Hedera Hashgraph, LLC).
/// @notice ABI of the Exchange Rate system contract at `0x0000000000000000000000000000000000000168` — the
///         network's USD/HBAR rate (file 0.0.112). 1 tinycent = 1e-8 US cent (1e-10 USD), 1 tinybar = 1e-8 HBAR.
interface IExchangeRate {
    function tinycentsToTinybars(uint256 tinycents) external returns (uint256 tinybars);
    function tinybarsToTinycents(uint256 tinybars) external returns (uint256 tinycents);
}
