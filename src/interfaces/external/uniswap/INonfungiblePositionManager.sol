// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title INonfungiblePositionManager
/// @author Modified from Uniswap V3 Periphery
///         (https://github.com/Uniswap/v3-periphery/blob/main/contracts/interfaces/INonfungiblePositionManager.sol)
/// @notice Minimal vendored subset of the Uniswap V3 NonfungiblePositionManager (NFPM): the ERC-721
///         that custodies concentrated-liquidity positions. The Lattice UniswapV3Adapter mints ONE
///         full-range position NFT and manages it through this surface.
/// @dev Vendored subset — do not add a uniswap-v3-periphery dependency. Only the selectors the
///      adapter calls are declared. All mutating params are passed as structs to mirror the real ABI
///      exactly (so the same calldata layout works against the canonical deployment).
interface INonfungiblePositionManager {
    /// @notice Params for `mint`.
    /// @param token0 The address of token0 (sorted; must equal the pool's token0).
    /// @param token1 The address of token1 (sorted; must equal the pool's token1).
    /// @param fee The pool fee tier (hundredths of a bip).
    /// @param tickLower The lower tick of the position (full-range: min usable tick).
    /// @param tickUpper The upper tick of the position (full-range: max usable tick).
    /// @param amount0Desired The desired amount of token0 to add.
    /// @param amount1Desired The desired amount of token1 to add.
    /// @param amount0Min The minimum amount of token0 to add (slippage floor).
    /// @param amount1Min The minimum amount of token1 to add (slippage floor).
    /// @param recipient The address that receives the minted position NFT.
    /// @param deadline The unix timestamp after which the mint reverts.
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    /// @notice Params for `increaseLiquidity`.
    /// @param tokenId The id of the position to add to.
    /// @param amount0Desired The desired amount of token0 to add.
    /// @param amount1Desired The desired amount of token1 to add.
    /// @param amount0Min The minimum amount of token0 to add (slippage floor).
    /// @param amount1Min The minimum amount of token1 to add (slippage floor).
    /// @param deadline The unix timestamp after which the call reverts.
    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Params for `decreaseLiquidity`.
    /// @param tokenId The id of the position to remove from.
    /// @param liquidity The amount of liquidity to remove.
    /// @param amount0Min The minimum amount of token0 owed after the burn (slippage floor).
    /// @param amount1Min The minimum amount of token1 owed after the burn (slippage floor).
    /// @param deadline The unix timestamp after which the call reverts.
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Params for `collect`.
    /// @param tokenId The id of the position to collect from.
    /// @param recipient The address that receives the collected tokens.
    /// @param amount0Max The maximum amount of token0 to collect.
    /// @param amount1Max The maximum amount of token1 to collect.
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    /// @notice Creates a new position wrapped in an NFT.
    /// @dev The caller must have approved both tokens to this contract. Reverts if a corresponding pool
    ///      does not exist or is uninitialized.
    /// @param params The mint params (token pair, fee, tick range, amounts, slippage floors, recipient).
    /// @return tokenId The id of the minted position NFT.
    /// @return liquidity The liquidity units added to the position.
    /// @return amount0 The amount of token0 actually consumed.
    /// @return amount1 The amount of token1 actually consumed.
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Increases the liquidity in an existing position.
    /// @param params The increase params (tokenId, amounts, slippage floors).
    /// @return liquidity The new liquidity units added.
    /// @return amount0 The amount of token0 actually consumed.
    /// @return amount1 The amount of token1 actually consumed.
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /// @notice Decreases the liquidity in a position. The freed amounts become owed-tokens collectable
    ///         via `collect` (they are NOT transferred by this call).
    /// @param params The decrease params (tokenId, liquidity to remove, slippage floors).
    /// @return amount0 The amount of token0 owed after the burn.
    /// @return amount1 The amount of token1 owed after the burn.
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    /// @notice Collects up to a maximum amount of owed tokens (freed liquidity + accrued fees) for a
    ///         position to `recipient`.
    /// @param params The collect params (tokenId, recipient, max amounts).
    /// @return amount0 The amount of token0 collected.
    /// @return amount1 The amount of token1 collected.
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);

    /// @notice Returns the full state of a position by token id.
    /// @param tokenId The id of the position to query.
    /// @return nonce The permit nonce (unused by the adapter).
    /// @return operator The approved operator (unused by the adapter).
    /// @return token0 The position's token0.
    /// @return token1 The position's token1.
    /// @return fee The position's fee tier.
    /// @return tickLower The position's lower tick.
    /// @return tickUpper The position's upper tick.
    /// @return liquidity The position's current liquidity (the quantity the adapter values via TWAP).
    /// @return feeGrowthInside0LastX128 Fee-growth checkpoint for token0 (unused by the adapter).
    /// @return feeGrowthInside1LastX128 Fee-growth checkpoint for token1 (unused by the adapter).
    /// @return tokensOwed0 Uncollected token0 owed to the position.
    /// @return tokensOwed1 Uncollected token1 owed to the position.
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
}
