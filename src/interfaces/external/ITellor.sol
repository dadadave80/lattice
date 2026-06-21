// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ITellor
/// @author Modified from Tellor (https://github.com/tellor-io)
/// @notice Minimal interface for the Tellor oracle (TellorFlex).
/// @dev Vendored subset — do not add a `usingtellor` dependency. Tellor is a dispute-based oracle:
///      reporters post data permissionlessly and bad values are removed by dispute. Best practice is to
///      read data at least a dispute buffer old (e.g. 15-20 min) via `getDataBefore` so disputed values
///      are removed first. SpotPrice `value` is `abi.encode(uint256)` at 18 decimals (WAD). Tellor is a
///      SINGLE global oracle contract per chain.
interface ITellor {
    /// @notice Returns the latest data before `timestamp` for `queryId`.
    /// @dev Reading data with a dispute buffer (`block.timestamp - buffer`) leaves time for disputed values
    ///      to be removed before they are consumed.
    /// @param queryId The Tellor query id (`keccak256(queryData)`).
    /// @param timestamp The exclusive upper-bound timestamp to read before.
    /// @return found True if a value was retrieved.
    /// @return value The reported value bytes (SpotPrice is `abi.encode(uint256)` at 18 decimals).
    /// @return timestampRetrieved The timestamp the returned value was reported.
    function getDataBefore(bytes32 queryId, uint256 timestamp)
        external
        view
        returns (bool found, bytes memory value, uint256 timestampRetrieved);
}
