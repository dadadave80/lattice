// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

/// @title IHyperbridgeNativeFeeRouter
/// @author Vendored minimal subset of Hyperbridge's native-fee quote wrappers (https://github.com/polytope-labs/hyperbridge/blob/b04bee03e4dd0b1c5958836994aabf2dfc09aa38/evm/src/utils/uniswapv2/UniV3UniswapV2Wrapper.sol).
///         Upstream license: Apache-2.0.
/// @notice The two quote methods of a host-configured Uniswap-V2-compatible fee router.
interface IHyperbridgeNativeFeeRouter {
    function WETH() external view returns (address);

    /// @dev Intentionally non-view: V3/V4 quote wrappers require a normal CALL, not STATICCALL.
    function getAmountsIn(uint256 amountOut, address[] calldata path) external returns (uint256[] memory amounts);
}
