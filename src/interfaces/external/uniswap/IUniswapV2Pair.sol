// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IUniswapV2Pair
/// @author Modified from Uniswap V2 (https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol)
/// @notice Minimal interface for Uniswap V2 pair contracts.
/// @dev Vendored subset covering cumulative prices and reserves — do not add a
///      uniswap-v2-core dependency.
interface IUniswapV2Pair {
    /// @notice Returns the cumulative price of token0 since the pair was created.
    function price0CumulativeLast() external view returns (uint256);

    /// @notice Returns the cumulative price of token1 since the pair was created.
    function price1CumulativeLast() external view returns (uint256);

    /// @notice Returns the current reserves of both tokens and the last update timestamp.
    /// @return reserve0             Reserve of token0.
    /// @return reserve1             Reserve of token1.
    /// @return blockTimestampLast   Timestamp of the last reserve update (mod 2**32).
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}
