// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ConstantProductLib} from "@lattice/amm/libraries/ConstantProductLib.sol";
import {IConstantProduct} from "@lattice/interfaces/IConstantProduct.sol";

/// @title ConstantProduct
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Uniswap V2 (https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol)
/// @notice Stateless Diamond facet for a Uniswap V2-style constant-product AMM.
/// @dev All logic lives in ConstantProductLib. This contract is a pure delegator.
///      Deploy as a facet in a Diamond proxy. Initialize via ConstantProductLib.__ConstantProduct_init.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Uniswap V2
contract ConstantProduct is IConstantProduct {
    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IConstantProduct
    function token0() public view virtual returns (address) {
        return ConstantProductLib.token0();
    }

    /// @inheritdoc IConstantProduct
    function token1() public view virtual returns (address) {
        return ConstantProductLib.token1();
    }

    /// @inheritdoc IConstantProduct
    function getReserves() public view virtual returns (uint256 reserve0, uint256 reserve1, uint32 blockTimestampLast) {
        return ConstantProductLib.getReserves();
    }

    /// @inheritdoc IConstantProduct
    function totalLpSupply() public view virtual returns (uint256) {
        return ConstantProductLib.totalLpSupply();
    }

    /// @inheritdoc IConstantProduct
    function lpBalanceOf(address account) public view virtual returns (uint256) {
        return ConstantProductLib.lpBalanceOf(account);
    }

    /// @inheritdoc IConstantProduct
    function feeBps() public pure virtual returns (uint16) {
        return ConstantProductLib.feeBps();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             MUTATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IConstantProduct
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) public virtual returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        return ConstantProductLib.addLiquidity(amount0Desired, amount1Desired, amount0Min, amount1Min, to);
    }

    /// @inheritdoc IConstantProduct
    function removeLiquidity(uint256 liquidity, uint256 amount0Min, uint256 amount1Min, address to)
        public
        virtual
        returns (uint256 amount0, uint256 amount1)
    {
        return ConstantProductLib.removeLiquidity(liquidity, amount0Min, amount1Min, to);
    }

    /// @inheritdoc IConstantProduct
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, bool zeroForOne, address to)
        public
        virtual
        returns (uint256 amountOut)
    {
        return ConstantProductLib.swapExactTokensForTokens(amountIn, amountOutMin, zeroForOne, to);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              QUOTE HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IConstantProduct
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        returns (uint256)
    {
        return ConstantProductLib.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /// @inheritdoc IConstantProduct
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        returns (uint256)
    {
        return ConstantProductLib.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    /// @inheritdoc IConstantProduct
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure virtual returns (uint256) {
        return ConstantProductLib.quote(amountA, reserveA, reserveB);
    }
}
