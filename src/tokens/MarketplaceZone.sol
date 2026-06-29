// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Schema, ZoneParameters} from "@lattice/interfaces/external/SeaportStructs.sol";
import {ZoneInterface} from "@lattice/interfaces/external/ZoneInterface.sol";
import {IMarketplaceZone} from "@lattice/interfaces/tokens/IMarketplaceZone.sol";
import {MarketplaceZoneLib} from "@lattice/tokens/libraries/MarketplaceZoneLib.sol";

/// @title MarketplaceZone
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Seaport 1.6 zone facet. The Diamond acts as the `zone` for RESTRICTED orders trading its tokens,
///         authorizing them only when policy holds: not paused, offerer/fulfiller not blocked, and the
///         ERC-2981 royalty present for opt-in collections.
/// @dev Stateless delegator — logic/storage live in {MarketplaceZoneLib}. `authorizeOrder` enforces pause +
///      blocklist (pre-fulfillment, skippable); `validateOrder` enforces royalties (post-fulfillment, final
///      amounts). Each returns its own selector as Seaport's magic value, else reverts. v1 of #25 — the
///      `ContractOffererInterface` (AMM-priced orders) facet is a separate v2 deliverable.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Seaport
contract MarketplaceZone is ZoneInterface, IMarketplaceZone {
    /// @inheritdoc ZoneInterface
    function authorizeOrder(ZoneParameters calldata zoneParameters) external virtual returns (bytes4) {
        return MarketplaceZoneLib.authorizeOrder(zoneParameters);
    }

    /// @inheritdoc ZoneInterface
    function validateOrder(ZoneParameters calldata zoneParameters) external virtual returns (bytes4) {
        return MarketplaceZoneLib.validateOrder(zoneParameters);
    }

    /// @inheritdoc ZoneInterface
    function getSeaportMetadata() external view virtual returns (string memory name, Schema[] memory schemas) {
        return MarketplaceZoneLib.getSeaportMetadata();
    }

    /// @inheritdoc IMarketplaceZone
    function zonePaused() external view virtual returns (bool) {
        return MarketplaceZoneLib.zonePaused();
    }

    /// @inheritdoc IMarketplaceZone
    function isRoyaltyRequired(address collection) external view virtual returns (bool) {
        return MarketplaceZoneLib.isRoyaltyRequired(collection);
    }

    /// @inheritdoc IMarketplaceZone
    function blockedRole() external pure virtual returns (bytes32) {
        return MarketplaceZoneLib.blockedRole();
    }

    /// @inheritdoc IMarketplaceZone
    function setPaused(bool paused_) external virtual {
        MarketplaceZoneLib.setPaused(paused_);
    }

    /// @inheritdoc IMarketplaceZone
    function setRoyaltyRequired(address collection, bool required) external virtual {
        MarketplaceZoneLib.setRoyaltyRequired(collection, required);
    }
}
