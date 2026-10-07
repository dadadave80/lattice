// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IHederaExchangeRateAdapter
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Interface for the HederaExchangeRateAdapter Diamond facet — the network's own USD/HBAR rate
///         (Exchange Rate system contract, file 0.0.112) exposed like the other Lattice price adapters.
/// @dev Units: 1 tinycent = 1e-8 US cent (1e-10 USD); 1 tinybar = 1e-8 HBAR = 1e10 weibar (`msg.value` units).
interface IHederaExchangeRateAdapter {
    /// @notice The Exchange Rate system contract halted or returned malformed data.
    error HederaExchangeRateCallFailed();

    /// @notice Converts USD tinycents to HBAR tinybars at the current network rate.
    function tinycentsToTinybars(uint256 tinycents) external view returns (uint256 tinybars);

    /// @notice Converts HBAR tinybars to USD tinycents at the current network rate.
    function tinybarsToTinycents(uint256 tinybars) external view returns (uint256 tinycents);

    /// @notice Converts whole USD cents to weibar (the `msg.value` unit) — e.g. to price a fee in USD.
    function usdCentsToWei(uint256 cents) external view returns (uint256 weibar);

    /// @notice Current HBAR/USD rate scaled to 18 decimals (USD per 1 HBAR, WAD), matching {latestAnswer}
    ///         conventions of the other oracle adapters.
    function hbarUsdWad() external view returns (uint256 priceWad);
}
