// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IApi3Proxy
/// @author Modified from API3 (https://github.com/api3dao/contracts)
/// @notice Minimal interface for an API3 dAPI reader proxy.
/// @dev Vendored subset — do not add an api3 contracts dependency. A dAPI is read through a
///      per-feed proxy contract; `value` is reported with 18 decimals (WAD) and `timestamp` is
///      the off-chain update time the consumer validates for staleness.
interface IApi3Proxy {
    /// @notice Reads the current dAPI value and its update timestamp.
    /// @return value The dAPI value, scaled to 1e18 (18 decimals).
    /// @return timestamp The timestamp the value was last updated off-chain.
    function read() external view returns (int224 value, uint32 timestamp);
}
