// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAirnodeRrpV0
/// @author Modified from API3 (https://github.com/api3dao/airnode/blob/master/packages/airnode-protocol/contracts/rrp/interfaces/IAirnodeRrpV0.sol)
/// @notice Minimal interface for the API3 Airnode Request-Response Protocol (RRP), used by QRNG.
/// @dev Vendored subset — do not add an api3 dependency. The Airnode fulfils a full request by calling
///      the registered `fulfillFunctionId` on `fulfillAddress`; that callback must verify
///      `msg.sender == airnodeRrp` (the `onlyAirnodeRrp` guard).
interface IAirnodeRrpV0 {
    /// @notice Sets whether `requester` is sponsored by the caller (the sponsor).
    /// @dev A full request only succeeds if its `sponsor` has sponsored its `requester`.
    /// @param requester          The requester contract being (un)sponsored.
    /// @param sponsorshipStatus  True to sponsor, false to revoke.
    function setSponsorshipStatus(address requester, bool sponsorshipStatus) external;

    /// @notice Makes a full request whose template + parameters are fully supplied on-chain.
    /// @param airnode            The Airnode address serving the request.
    /// @param endpointId         The endpoint identifier on that Airnode.
    /// @param sponsor            The sponsor account funding fulfilment via `sponsorWallet`.
    /// @param sponsorWallet      The wallet (derived from the sponsor) that pays for fulfilment gas.
    /// @param fulfillAddress     The contract the Airnode calls back.
    /// @param fulfillFunctionId  The selector the Airnode calls on `fulfillAddress`.
    /// @param parameters         ABI-encoded request parameters (encoded per Airnode ABI spec).
    /// @return requestId The identifier assigned to this request.
    function makeFullRequest(
        address airnode,
        bytes32 endpointId,
        address sponsor,
        address sponsorWallet,
        address fulfillAddress,
        bytes4 fulfillFunctionId,
        bytes calldata parameters
    ) external returns (bytes32 requestId);
}
