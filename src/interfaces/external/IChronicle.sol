// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IChronicle
/// @author Modified from Chronicle (https://github.com/chronicleprotocol)
/// @notice Minimal interface for a Chronicle oracle feed.
/// @dev Vendored subset — do not add a chronicle-std dependency. Chronicle oracles are Schnorr-signed
///      and publish values already scaled to 1e18 (WAD). Reads are **toll-gated**: the consuming contract
///      must be whitelisted by the oracle operator via `kiss(address)` before `read()` or `readWithAge()`
///      will succeed. Without whitelisting, calls revert.
interface IChronicle {
    /// @notice Reads the current oracle value.
    /// @return value The oracle value, scaled to 1e18 (18 decimals, WAD).
    function read() external view returns (uint256 value);

    /// @notice Reads the current oracle value and the timestamp it was last written.
    /// @return value The oracle value, scaled to 1e18 (18 decimals, WAD).
    /// @return age   The Unix timestamp at which the value was last written on-chain.
    function readWithAge() external view returns (uint256 value, uint256 age);
}
