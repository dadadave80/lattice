// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IConstantProduct
/// @author Modified from Uniswap V2 (https://github.com/Uniswap/v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol)
/// @notice Interface for the Constant Product AMM (Uniswap V2 style) Diamond facet.
/// @dev Manages a single x*y=k pool with two ERC-20 reserves and LP token accounting.
interface IConstantProduct {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Emitted when liquidity is added to the pool.
    /// @param provider The address that called addLiquidity.
    /// @param to The address that received the LP shares.
    /// @param amount0 The amount of token0 deposited.
    /// @param amount1 The amount of token1 deposited.
    /// @param liquidity The amount of LP shares minted.
    event LiquidityAdded(
        address indexed provider, address indexed to, uint256 amount0, uint256 amount1, uint256 liquidity
    );

    /// @dev Emitted when liquidity is removed from the pool.
    /// @param provider The address that called removeLiquidity.
    /// @param to The address that received the underlying tokens.
    /// @param amount0 The amount of token0 returned.
    /// @param amount1 The amount of token1 returned.
    /// @param liquidity The amount of LP shares burned.
    event LiquidityRemoved(
        address indexed provider, address indexed to, uint256 amount0, uint256 amount1, uint256 liquidity
    );

    /// @dev Emitted on every swap.
    /// @param sender The address that initiated the swap.
    /// @param to The address that received the output tokens.
    /// @param amount0In The amount of token0 sent in.
    /// @param amount1In The amount of token1 sent in.
    /// @param amount0Out The amount of token0 sent out.
    /// @param amount1Out The amount of token1 sent out.
    event Swap(
        address indexed sender,
        address indexed to,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out
    );

    /// @dev Emitted when the pool reserves are synced to the actual balances.
    /// @param reserve0 The updated reserve of token0.
    /// @param reserve1 The updated reserve of token1.
    event ReservesSync(uint256 reserve0, uint256 reserve1);

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Raised when the pool is already initialized.
    error ConstantProductAlreadyInitialized();

    /// @dev Raised when the supplied token addresses are invalid (identical or zero).
    error ConstantProductInvalidTokens();

    /// @dev Raised when the computed LP liquidity to mint is zero.
    error ConstantProductInsufficientLiquidityMinted();

    /// @dev Raised when the computed token amounts to return on burn are zero.
    error ConstantProductInsufficientLiquidityBurned();

    /// @dev Raised when the swap input amount is zero.
    error ConstantProductInsufficientInputAmount();

    /// @dev Raised when the swap output does not meet the caller's minimum.
    error ConstantProductInsufficientOutputAmount();

    /// @dev Raised when a reserve is zero during a quote or swap calculation.
    error ConstantProductInsufficientLiquidity();

    /// @dev Raised when the k invariant check fails after a swap.
    error ConstantProductInvalidK();

    /// @dev Raised when a token transfer (in or out) returns false.
    /// @param token The token address that failed to transfer.
    error ConstantProductTransferFailed(address token);

    /// @dev Raised when a reserve update would exceed the uint112 maximum (~5.19e33).
    /// @dev This is only reachable for tokens with astronomically large supplies.
    error ConstantProductReserveOverflow();

    /// @dev Raised when the actual amounts deposited or received fall below the caller's minimums.
    error ConstantProductSlippageExceeded();

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the address of the lower-sorted pool token.
    function token0() external view returns (address);

    /// @notice Returns the address of the higher-sorted pool token.
    function token1() external view returns (address);

    /// @notice Returns the current reserves and the block timestamp of the last update.
    /// @return reserve0 Reserve of token0.
    /// @return reserve1 Reserve of token1.
    /// @return blockTimestampLast Unix timestamp (mod 2^32) of the last reserve update.
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint32 blockTimestampLast);

    /// @notice Returns the total supply of LP shares.
    function totalLpSupply() external view returns (uint256);

    /// @notice Returns the LP share balance of `account`.
    /// @param account The address to query.
    function lpBalanceOf(address account) external view returns (uint256);

    /// @notice Returns the swap fee in basis points (always 30 = 0.3%).
    function feeBps() external view returns (uint16);

    //*//////////////////////////////////////////////////////////////////////////
    //                             MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Adds liquidity to the pool and mints LP shares to `to`.
    /// @param amount0Desired The desired amount of token0 to deposit.
    /// @param amount1Desired The desired amount of token1 to deposit.
    /// @param amount0Min The minimum acceptable amount of token0 (slippage guard).
    /// @param amount1Min The minimum acceptable amount of token1 (slippage guard).
    /// @param to The recipient of the minted LP shares.
    /// @return amount0 Actual amount of token0 deposited.
    /// @return amount1 Actual amount of token1 deposited.
    /// @return liquidity LP shares minted to `to`.
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external returns (uint256 amount0, uint256 amount1, uint256 liquidity);

    /// @notice Burns LP shares from the caller and returns the underlying tokens to `to`.
    /// @param liquidity The amount of LP shares to burn.
    /// @param amount0Min The minimum acceptable amount of token0 (slippage guard).
    /// @param amount1Min The minimum acceptable amount of token1 (slippage guard).
    /// @param to The recipient of the underlying tokens.
    /// @return amount0 Amount of token0 returned.
    /// @return amount1 Amount of token1 returned.
    function removeLiquidity(uint256 liquidity, uint256 amount0Min, uint256 amount1Min, address to)
        external
        returns (uint256 amount0, uint256 amount1);

    /// @notice Swaps an exact input amount for as many output tokens as possible.
    /// @param amountIn The exact amount of input token to sell.
    /// @param amountOutMin The minimum acceptable output amount (slippage guard).
    /// @param zeroForOne True if selling token0 for token1; false if selling token1 for token0.
    /// @param to The recipient of the output tokens.
    /// @return amountOut The amount of output tokens sent to `to`.
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, bool zeroForOne, address to)
        external
        returns (uint256 amountOut);

    //*//////////////////////////////////////////////////////////////////////////
    //                              QUOTE HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Computes the output amount given an input amount and pool reserves (with fee).
    /// @param amountIn The input amount.
    /// @param reserveIn The reserve of the input token.
    /// @param reserveOut The reserve of the output token.
    /// @return The output amount after the 0.3% fee.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256);

    /// @notice Computes the required input amount to receive a specific output amount (with fee).
    /// @param amountOut The desired output amount.
    /// @param reserveIn The reserve of the input token.
    /// @param reserveOut The reserve of the output token.
    /// @return The required input amount before fee.
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256);

    /// @notice Returns the equivalent amount of tokenB given an amount of tokenA at the current ratio.
    /// @dev Used to compute proportional token amounts for liquidity provision. No fee applied.
    /// @param amountA The amount of tokenA.
    /// @param reserveA The reserve of tokenA.
    /// @param reserveB The reserve of tokenB.
    /// @return The equivalent amount of tokenB.
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256);
}
