// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IDIAOracleV2
/// @author Modified from DIA (https://github.com/diadata-org)
/// @notice Minimal interface for a DIA OracleV2 contract.
/// @dev Vendored subset — do not add a DIA dependency. A single DIA oracle contract serves many
///      string-keyed feeds (e.g. "ETH/USD"); `value` is reported with 8 decimals and `timestamp`
///      is the off-chain update time the consumer validates for staleness.
interface IDIAOracleV2 {
    /// @notice Reads the current value and update timestamp for the given key.
    /// @param key The DIA price key string (e.g. "ETH/USD").
    /// @return value The price value, scaled to 1e8 (8 decimals).
    /// @return timestamp The timestamp the value was last updated off-chain.
    function getValue(string memory key) external view returns (uint128 value, uint128 timestamp);
}
