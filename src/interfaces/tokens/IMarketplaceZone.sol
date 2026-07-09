// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IMarketplaceZone
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Seaport (https://github.com/ProjectOpenSea/seaport)
/// @notice Admin/read surface of the Seaport `MarketplaceZone` facet. The Seaport hooks themselves
///         (`authorizeOrder` / `validateOrder` / `getSeaportMetadata`) are on the vendored `ZoneInterface`.
/// @dev The zone authorizes RESTRICTED Seaport orders that name the Diamond as their zone. v1 policy:
///      a global pause (kill-switch), a sanctions-style blocklist on the order's offerer/fulfiller
///      (`MARKETPLACE_BLOCKED_ROLE`), and per-collection ERC-2981 royalty enforcement. Pause + blocklist are
///      checked in `authorizeOrder` (pre-fulfillment, so failing orders are skippable in `fulfillAvailable*`);
///      royalties are enforced in `validateOrder` (post-fulfillment, against final amounts).
///
///      v1 royalty scope — to never SILENTLY bypass enforcement, the zone only enforces the cleanly-decidable
///      case and REVERTS the rest: exactly one opted-in NFT on the OFFER side (an ask/listing), paid in a
///      single fungible currency. Bid/offer-side orders (opted-in NFT in consideration), multi-NFT bundles,
///      zero-price orders, and opted-in collections whose `royaltyInfo` reverts are all rejected (not allowed
///      royalty-free). Full bid/bundle/multi-currency support is a v2 follow-on.
interface IMarketplaceZone {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the global pause flag is set.
    event SetPaused(bool paused);

    /// @notice Emitted when a collection's ERC-2981 royalty enforcement is toggled.
    event SetRoyaltyRequired(address indexed collection, bool required);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The zone is paused; no order is authorized.
    error ZonePaused();

    /// @notice The order's offerer or fulfiller holds `MARKETPLACE_BLOCKED_ROLE`.
    error BlockedParticipant(address account);

    /// @notice The order's consideration does not pay the required ERC-2981 royalty.
    error MissingRoyalty(address collection, uint256 tokenId, address receiver, uint256 required, uint256 provided);

    /// @notice The order mixes payment currencies; v1 royalty enforcement requires a single fungible currency.
    error MixedPaymentCurrency();

    /// @notice An opted-in NFT is on the consideration (bid) side; v1 only enforces royalties on ask listings.
    error BidOrdersUnsupported();

    /// @notice More than one opted-in NFT is offered; v1 does not enforce royalties on bundles.
    error BundleOrdersUnsupported();

    /// @notice An opted-in NFT is sold for zero fungible price (barter); v1 cannot enforce a royalty on it.
    error ZeroPriceRoyaltyOrder();

    /// @notice An opted-in collection's `royaltyInfo` reverted, so the royalty cannot be enforced.
    error RoyaltyInfoUnavailable(address collection);

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice Whether the zone is paused. (Named `zonePaused` to avoid the `Pausable` facet's `paused()` selector.)
    function zonePaused() external view returns (bool);

    /// @notice Whether `collection` requires its ERC-2981 royalty to be present in the order's consideration.
    function isRoyaltyRequired(address collection) external view returns (bool);

    /// @notice The role that blocks an address from being an order's offerer or fulfiller.
    function blockedRole() external pure returns (bytes32);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Sets the global pause flag. Admin only.
    function setPaused(bool paused) external;

    /// @notice Toggles ERC-2981 royalty enforcement for `collection`. Admin only.
    function setRoyaltyRequired(address collection, bool required) external;
}
