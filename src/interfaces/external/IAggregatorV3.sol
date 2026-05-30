// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAggregatorV3
/// @notice Minimal interface for Chainlink AggregatorV3 price feeds.
/// @dev Vendored subset — do not add a chainlink-brownie-contracts dependency.
interface IAggregatorV3 {
    /// @notice Returns the number of decimals in the feed's answer.
    function decimals() external view returns (uint8);

    /// @notice Returns a human-readable description of the feed (e.g. "ETH / USD").
    function description() external view returns (string memory);

    /// @notice Returns the latest round data from the feed.
    /// @return roundId      The round ID.
    /// @return answer       The price answer.
    /// @return startedAt    Timestamp when the round started.
    /// @return updatedAt    Timestamp when the round was last updated.
    /// @return answeredInRound The round ID in which the answer was computed.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
