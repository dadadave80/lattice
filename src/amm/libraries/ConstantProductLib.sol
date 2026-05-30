// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IConstantProduct} from "@lattice/interfaces/IConstantProduct.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {IERC20} from "@lattice/interfaces/IERC20.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ConstantProduct")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CONSTANT_PRODUCT_STORAGE_SLOT = 0xf3baf196a9957c5a93606e180cd873c83f4d725c3513c9295ef6ca05f13a2200;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CP_ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev Precomputed ERC-165 map slot for IConstantProduct.
/// `0x8098801f` is `type(IConstantProduct).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x8098801f), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICONSTANTPRODUCT_SLOT = 0xe179134a78bc5c2b2530eee9483cf7fd81654d9311d88e7b22e0fa63d02f43cf;

/// @notice Storage struct for ConstantProduct AMM module.
/// @custom:storage-location erc7201:lattice.storage.ConstantProduct
struct ConstantProductStorage {
    address _token0;
    address _token1;
    uint112 _reserve0;
    uint112 _reserve1;
    uint32 _blockTimestampLast;
    uint256 _totalLpSupply;
    mapping(address account => uint256) _lpBalances;
    bool _initialized;
}

/// @title ConstantProductLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing a Uniswap V2-style constant-product AMM (x*y=k) as a stateless Diamond facet.
/// @dev All state lives in a single ERC-7201 namespaced slot. LP shares are tracked internally
///      (not as a separate ERC-20 token) to avoid an extra facet dependency. 0.3% swap fee (30 bps).
library ConstantProductLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                 CONSTANTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Swap fee in basis points (0.3%).
    uint16 internal constant FEE_BPS = 30;

    /// @notice Minimum liquidity permanently locked on first deposit (Uniswap V2 convention).
    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ConstantProduct storage struct.
    function constantProductStorage() internal pure returns (ConstantProductStorage storage $) {
        assembly {
            $.slot := CONSTANT_PRODUCT_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ConstantProduct pool with two ERC-20 token addresses.
    /// @dev Must be called inside a pre/postInitializer block. Sorts tokens so token0 < token1.
    /// @param tokenA One of the two pool tokens.
    /// @param tokenB The other pool token.
    function __ConstantProduct_init(address tokenA, address tokenB) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);

        if (tokenA == tokenB || tokenA == address(0) || tokenB == address(0)) {
            revert IConstantProduct.ConstantProductInvalidTokens();
        }

        ConstantProductStorage storage $ = constantProductStorage();

        if ($._initialized) revert IConstantProduct.ConstantProductAlreadyInitialized();

        // Sort tokens so token0 is always the lower address.
        (address token0_, address token1_) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        $._token0 = token0_;
        $._token1 = token1_;
        $._initialized = true;

        ReentrancyGuardLib.__ReentrancyGuard_init();
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for IConstantProduct via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ICONSTANTPRODUCT_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns token0 address.
    function token0() internal view returns (address) {
        return constantProductStorage()._token0;
    }

    /// @notice Returns token1 address.
    function token1() internal view returns (address) {
        return constantProductStorage()._token1;
    }

    /// @notice Returns the current reserves and last-update timestamp.
    function getReserves() internal view returns (uint256 reserve0, uint256 reserve1, uint32 blockTimestampLast) {
        ConstantProductStorage storage $ = constantProductStorage();
        return (uint256($._reserve0), uint256($._reserve1), $._blockTimestampLast);
    }

    /// @notice Returns the total LP share supply.
    function totalLpSupply() internal view returns (uint256) {
        return constantProductStorage()._totalLpSupply;
    }

    /// @notice Returns the LP share balance of `account`.
    function lpBalanceOf(address account) internal view returns (uint256) {
        return constantProductStorage()._lpBalances[account];
    }

    /// @notice Returns the swap fee in basis points (always 30).
    function feeBps() internal pure returns (uint16) {
        return FEE_BPS;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              LIQUIDITY: ADD
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Adds liquidity to the pool and mints LP shares to `to`.
    /// @param amount0Desired Desired deposit of token0.
    /// @param amount1Desired Desired deposit of token1.
    /// @param amount0Min Minimum acceptable token0 deposit (slippage guard).
    /// @param amount1Min Minimum acceptable token1 deposit (slippage guard).
    /// @param to Recipient of minted LP shares.
    /// @return amount0 Actual token0 deposited.
    /// @return amount1 Actual token1 deposited.
    /// @return liquidity LP shares minted to `to`.
    function addLiquidity(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) internal returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        ReentrancyGuardLib.nonReentrantBefore();

        ConstantProductStorage storage $ = constantProductStorage();
        uint256 reserve0_ = uint256($._reserve0);
        uint256 reserve1_ = uint256($._reserve1);

        if (reserve0_ == 0 && reserve1_ == 0) {
            // First deposit: price is set by the depositor.
            amount0 = amount0Desired;
            amount1 = amount1Desired;
        } else {
            // Compute optimal amount1 given amount0Desired.
            uint256 amount1Optimal = quote(amount0Desired, reserve0_, reserve1_);
            if (amount1Optimal <= amount1Desired) {
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                // amount1Desired is the binding constraint — back-calculate amount0.
                uint256 amount0Optimal = quote(amount1Desired, reserve1_, reserve0_);
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
        }

        // Slippage checks.
        require(amount0 >= amount0Min && amount1 >= amount1Min);

        address caller = ContextLib.msgSender();

        // CHECKS-EFFECTS-INTERACTIONS: compute LP shares and update all storage
        // BEFORE any external token calls to prevent reentrancy attacks.

        // Compute LP shares to mint.
        uint256 totalSupply_ = $._totalLpSupply;
        if (totalSupply_ == 0) {
            uint256 raw = _sqrt(amount0 * amount1);
            // Revert if sqrt rounds to 0 before subtracting MINIMUM_LIQUIDITY.
            if (raw <= MINIMUM_LIQUIDITY) revert IConstantProduct.ConstantProductInsufficientLiquidityMinted();
            liquidity = raw - MINIMUM_LIQUIDITY;
            // Permanently lock MINIMUM_LIQUIDITY to address(1).
            _mintLp($, address(1), MINIMUM_LIQUIDITY);
        } else {
            uint256 liq0 = (amount0 * totalSupply_) / reserve0_;
            uint256 liq1 = (amount1 * totalSupply_) / reserve1_;
            liquidity = liq0 < liq1 ? liq0 : liq1;
        }

        if (liquidity == 0) revert IConstantProduct.ConstantProductInsufficientLiquidityMinted();

        // EFFECTS: mint LP shares and update reserves BEFORE external calls.
        _mintLp($, to, liquidity);
        $._reserve0 = uint112(reserve0_ + amount0);
        $._reserve1 = uint112(reserve1_ + amount1);
        $._blockTimestampLast = uint32(block.timestamp);

        emit IConstantProduct.LiquidityAdded(caller, to, amount0, amount1, liquidity);
        emit IConstantProduct.ReservesSync(uint256($._reserve0), uint256($._reserve1));

        // INTERACTIONS: pull tokens from caller after all state is updated.
        _safeTransferFrom($._token0, caller, address(this), amount0);
        _safeTransferFrom($._token1, caller, address(this), amount1);

        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             LIQUIDITY: REMOVE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Burns LP shares from the caller and returns underlying tokens to `to`.
    /// @param liquidity Amount of LP shares to burn.
    /// @param amount0Min Minimum acceptable token0 returned (slippage guard).
    /// @param amount1Min Minimum acceptable token1 returned (slippage guard).
    /// @param to Recipient of the returned tokens.
    /// @return amount0 Amount of token0 returned.
    /// @return amount1 Amount of token1 returned.
    function removeLiquidity(uint256 liquidity, uint256 amount0Min, uint256 amount1Min, address to)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        ReentrancyGuardLib.nonReentrantBefore();

        ConstantProductStorage storage $ = constantProductStorage();
        uint256 totalSupply_ = $._totalLpSupply;
        uint256 reserve0_ = uint256($._reserve0);
        uint256 reserve1_ = uint256($._reserve1);

        amount0 = (liquidity * reserve0_) / totalSupply_;
        amount1 = (liquidity * reserve1_) / totalSupply_;

        if (amount0 == 0 || amount1 == 0) revert IConstantProduct.ConstantProductInsufficientLiquidityBurned();

        // Slippage checks.
        require(amount0 >= amount0Min && amount1 >= amount1Min);

        address caller = ContextLib.msgSender();

        // EFFECTS: burn LP shares and update reserves BEFORE external transfers.
        _burnLp($, caller, liquidity);
        $._reserve0 = uint112(reserve0_ - amount0);
        $._reserve1 = uint112(reserve1_ - amount1);
        $._blockTimestampLast = uint32(block.timestamp);

        emit IConstantProduct.LiquidityRemoved(caller, to, amount0, amount1, liquidity);
        emit IConstantProduct.ReservesSync(uint256($._reserve0), uint256($._reserve1));

        // INTERACTIONS: transfer underlying tokens after all state is updated.
        _safeTransfer($._token0, to, amount0);
        _safeTransfer($._token1, to, amount1);

        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  SWAP
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Swaps an exact input amount for output tokens.
    /// @param amountIn Exact input token amount to sell.
    /// @param amountOutMin Minimum acceptable output (slippage guard).
    /// @param zeroForOne True = sell token0 for token1; False = sell token1 for token0.
    /// @param to Recipient of output tokens.
    /// @return amountOut Output token amount sent to `to`.
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, bool zeroForOne, address to)
        internal
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert IConstantProduct.ConstantProductInsufficientInputAmount();

        ReentrancyGuardLib.nonReentrantBefore();

        ConstantProductStorage storage $ = constantProductStorage();

        address caller = ContextLib.msgSender();
        amountOut = _executeSwap($, amountIn, amountOutMin, zeroForOne, caller, to);

        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @dev Internal helper that carries out the swap to avoid stack-too-deep in the public entry point.
    ///      CEI order: CHECKS → EFFECTS (reserve update) → INTERACTIONS (token transfers).
    function _executeSwap(
        ConstantProductStorage storage $,
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        address caller,
        address to
    ) private returns (uint256 amountOut) {
        uint256 reserve0_ = uint256($._reserve0);
        uint256 reserve1_ = uint256($._reserve1);

        uint256 reserveIn = zeroForOne ? reserve0_ : reserve1_;
        uint256 reserveOut = zeroForOne ? reserve1_ : reserve0_;
        address tokenIn = zeroForOne ? $._token0 : $._token1;
        address tokenOut = zeroForOne ? $._token1 : $._token0;

        // CHECKS: compute and validate output amount.
        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);

        if (amountOut < amountOutMin) revert IConstantProduct.ConstantProductInsufficientOutputAmount();

        // K invariant check.
        _checkK(amountIn, amountOut, reserveIn, reserveOut);

        // EFFECTS: update reserves BEFORE any external token calls.
        if (zeroForOne) {
            $._reserve0 = uint112(reserve0_ + amountIn);
            $._reserve1 = uint112(reserve1_ - amountOut);
            emit IConstantProduct.Swap(caller, to, amountIn, 0, 0, amountOut);
        } else {
            $._reserve0 = uint112(reserve0_ - amountOut);
            $._reserve1 = uint112(reserve1_ + amountIn);
            emit IConstantProduct.Swap(caller, to, 0, amountIn, amountOut, 0);
        }
        $._blockTimestampLast = uint32(block.timestamp);

        emit IConstantProduct.ReservesSync(uint256($._reserve0), uint256($._reserve1));

        // INTERACTIONS: pull input, then push output.
        _safeTransferFrom(tokenIn, caller, address(this), amountIn);
        _safeTransfer(tokenOut, to, amountOut);
    }

    /// @dev Validates that the constant-product invariant holds after a swap.
    function _checkK(uint256 amountIn, uint256 amountOut, uint256 reserveIn, uint256 reserveOut) private pure {
        // (reserveIn * 10000 + amountIn * (10000 - FEE_BPS)) * (reserveOut - amountOut)
        //   >= reserveIn * reserveOut * 10000
        uint256 lhs = (reserveIn * 10000 + amountIn * (10000 - FEE_BPS)) * (reserveOut - amountOut);
        uint256 rhs = reserveIn * reserveOut * 10000;
        if (lhs < rhs) revert IConstantProduct.ConstantProductInvalidK();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              QUOTE HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Computes the output amount given an input amount and pool reserves, applying the 0.3% fee.
    /// @param amountIn The input amount.
    /// @param reserveIn The reserve of the input token.
    /// @param reserveOut The reserve of the output token.
    /// @return amountOut The output amount after fee.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        if (reserveIn == 0 || reserveOut == 0) revert IConstantProduct.ConstantProductInsufficientLiquidity();
        uint256 amountInWithFee = amountIn * (10000 - FEE_BPS);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 10000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice Computes the required input to receive a specific output amount, applying the 0.3% fee.
    /// @param amountOut The desired output amount.
    /// @param reserveIn The reserve of the input token.
    /// @param reserveOut The reserve of the output token.
    /// @return amountIn The required input amount (rounded up).
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        if (reserveIn == 0 || reserveOut == 0) revert IConstantProduct.ConstantProductInsufficientLiquidity();
        if (amountOut >= reserveOut) revert IConstantProduct.ConstantProductInsufficientLiquidity();
        uint256 numerator = reserveIn * amountOut * 10000;
        uint256 denominator = (reserveOut - amountOut) * (10000 - FEE_BPS);
        amountIn = numerator / denominator + 1;
    }

    /// @notice Returns the equivalent amount of tokenB given amountA at the current pool ratio.
    /// @dev No fee is applied — this is used for liquidity proportion calculations.
    /// @param amountA Amount of tokenA.
    /// @param reserveA Reserve of tokenA.
    /// @param reserveB Reserve of tokenB.
    /// @return amountB Equivalent amount of tokenB.
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        if (reserveA == 0) revert IConstantProduct.ConstantProductInsufficientLiquidity();
        amountB = amountA * reserveB / reserveA;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Babylonian square-root used for first-liquidity LP share calculation.
    /// @param y The value to take the square root of.
    /// @return z The integer square root of `y`.
    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /// @notice Mints LP shares to `account`, updating total supply.
    function _mintLp(ConstantProductStorage storage $, address account, uint256 amount) private {
        $._totalLpSupply += amount;
        $._lpBalances[account] += amount;
    }

    /// @notice Burns LP shares from `account`, updating total supply.
    function _burnLp(ConstantProductStorage storage $, address account, uint256 amount) private {
        $._lpBalances[account] -= amount;
        $._totalLpSupply -= amount;
    }

    /// @notice Calls `transferFrom` on `token`, reverts with ConstantProductTransferFailed on false return.
    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        bool ok = IERC20(token).transferFrom(from, to, amount);
        if (!ok) revert IConstantProduct.ConstantProductTransferFailed(token);
    }

    /// @notice Calls `transfer` on `token`, reverts with ConstantProductTransferFailed on false return.
    function _safeTransfer(address token, address to, uint256 amount) private {
        bool ok = IERC20(token).transfer(to, amount);
        if (!ok) revert IConstantProduct.ConstantProductTransferFailed(token);
    }
}
