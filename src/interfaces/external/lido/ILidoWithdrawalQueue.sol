// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ILidoWithdrawalQueue
/// @author Modified from Lido WithdrawalQueueERC721
///         (https://github.com/lidofinance/lido-dao/blob/master/contracts/0.8.9/WithdrawalQueueERC721.sol)
/// @notice Minimal vendored subset of the Lido withdrawal queue. Lido withdrawals are an **async
///         queue**: requesting burns stETH and mints an NFT request id that becomes claimable only
///         after the protocol finalizes it (oracle report + buffer), at which point claiming pays
///         out native ETH. This async leg is why the Lido adapter uses a buffer model — the
///         synchronous `IStrategy.withdraw` is served from an idle WETH buffer, and the slow queue
///         leg runs out-of-band via the adapter's keeper functions.
/// @dev Only the selectors the adapter calls are declared. `requestWithdrawals` /
///      `claimWithdrawal` move funds (non-`view`); `getWithdrawalStatus` is a `view` reader for the
///      pending/finalized/claimed flags. The adapter requests with `owner == address(this)` and
///      claims to itself, re-wrapping the received ETH into its WETH buffer.
interface ILidoWithdrawalQueue {
    /// @notice Per-request status returned by `getWithdrawalStatus`.
    /// @param amountOfStETH       stETH that was locked for this request.
    /// @param amountOfShares      Lido shares locked for this request.
    /// @param owner               The address that owns the request (the claimer).
    /// @param timestamp           Block timestamp the request was created.
    /// @param isFinalized         True once the request is finalized and claimable.
    /// @param isClaimed           True once the request's ETH has been claimed.
    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    /// @notice Locks `amounts` of stETH (pulled from the caller; the adapter approves first) and mints
    ///         one withdrawal-request NFT per entry to `owner`.
    /// @param amounts Per-request stETH amounts to withdraw.
    /// @param owner   The owner of the minted request NFTs (the claimer; the adapter passes itself).
    /// @return requestIds The ids of the created withdrawal requests, index-aligned with `amounts`.
    function requestWithdrawals(uint256[] calldata amounts, address owner)
        external
        returns (uint256[] memory requestIds);

    /// @notice Claims a finalized withdrawal request, sending the owed native ETH to the request owner.
    /// @param requestId The id of the finalized request to claim.
    function claimWithdrawal(uint256 requestId) external;

    /// @notice Returns the status of each requested withdrawal id.
    /// @param requestIds The request ids to query.
    /// @return statuses The status struct for each id, index-aligned with `requestIds`.
    function getWithdrawalStatus(uint256[] calldata requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);
}
