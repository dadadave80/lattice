// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IRedstonePriceFeedsAdapter
/// @author Modified from RedStone (https://github.com/redstone-finance/redstone-oracles-monorepo)
/// @notice Minimal interface for a RedStone Push `PriceFeedsAdapter` contract.
/// @dev Vendored subset — do not add a redstone dependency. RedStone's Push model stores signed values
///      on-chain (updated in batches); a consumer reads the stored value for a `dataFeedId` and the
///      timestamps of the latest update. Values are reported with 8 decimals; `dataTimestamp` is in
///      milliseconds (the off-chain data time) while `blockTimestamp` is in seconds (the on-chain update
///      time used for staleness).
interface IRedstonePriceFeedsAdapter {
    /// @notice Returns the latest stored value for a RedStone data feed.
    /// @param dataFeedId The RedStone data-feed id (e.g. `bytes32("ETH")`).
    /// @return value The stored value, scaled to 8 decimals.
    function getValueForDataFeed(bytes32 dataFeedId) external view returns (uint256 value);

    /// @notice Returns the timestamps of the latest batch update.
    /// @return dataTimestamp The off-chain data timestamp, in milliseconds.
    /// @return blockTimestamp The on-chain update timestamp, in seconds.
    function getTimestampsFromLatestUpdate() external view returns (uint128 dataTimestamp, uint128 blockTimestamp);
}
