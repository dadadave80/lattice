// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IPyth
/// @author Modified from Pyth Network (https://github.com/pyth-network/pyth-crosschain/blob/main/target_chains/ethereum/sdk/solidity/IPyth.sol)
/// @notice Minimal interface for the Pyth on-chain price oracle.
/// @dev Vendored subset — do not add a `@pythnetwork/pyth-sdk-solidity` dependency. Pyth is pull-based:
///      a caller submits a signed `updateData` blob (paying `getUpdateFee`) via `updatePriceFeeds`,
///      which stores the latest price on-chain; reads then use `getPriceUnsafe` (raw, no staleness check
///      — the consumer validates publish time itself).
interface IPyth {
    /// @notice A Pyth price with its confidence interval and exponent.
    /// @param price The price (scale `10^expo`).
    /// @param conf The confidence interval around `price` (same scale).
    /// @param expo The price exponent (usually negative, e.g. -8).
    /// @param publishTime The unix timestamp the price was published.
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    /// @notice Returns the latest price for `id` WITHOUT a staleness check.
    /// @dev Reverts if no price has ever been posted for `id`. The caller MUST check `publishTime`.
    /// @param id The Pyth price-feed id.
    /// @return price The latest stored price.
    function getPriceUnsafe(bytes32 id) external view returns (Price memory price);

    /// @notice Returns the fee (in wei) required to submit `updateData`.
    /// @param updateData The signed price-update blobs.
    /// @return feeAmount The required fee.
    function getUpdateFee(bytes[] calldata updateData) external view returns (uint256 feeAmount);

    /// @notice Submits `updateData` to update the on-chain prices; `msg.value` must be `>= getUpdateFee`.
    /// @param updateData The signed price-update blobs.
    function updatePriceFeeds(bytes[] calldata updateData) external payable;
}
