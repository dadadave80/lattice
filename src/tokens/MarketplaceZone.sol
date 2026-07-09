// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Schema, ZoneParameters} from "@lattice/interfaces/external/SeaportStructs.sol";
import {ZoneInterface} from "@lattice/interfaces/external/ZoneInterface.sol";
import {IMarketplaceZone} from "@lattice/interfaces/tokens/IMarketplaceZone.sol";
import {MarketplaceZoneLib} from "@lattice/tokens/libraries/MarketplaceZoneLib.sol";

/// @title MarketplaceZone
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Seaport (https://github.com/ProjectOpenSea/seaport)
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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect MarketplaceZone methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `authorizeOrder((bytes32,address,address,(uint8,address,uint256,uint256)[],(uint8,address,uint256,uint256,address)[],bytes,bytes32[],uint256,uint256,bytes32))` 0x01e4d72a
    ///      `blockedRole()` 0x1a5194be
    ///      `getSeaportMetadata()` 0x2e778efc
    ///      `isRoyaltyRequired(address)` 0x50dacc83
    ///      `setPaused(bool)` 0x16c38b3c
    ///      `setRoyaltyRequired(address,bool)` 0xd98a7d79
    ///      `validateOrder((bytes32,address,address,(uint8,address,uint256,uint256)[],(uint8,address,uint256,uint256,address)[],bytes,bytes32[],uint256,uint256,bytes32))` 0x17b1f942
    ///      `zonePaused()` 0x1a405ea4
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"01e4d72a1a5194be2e778efc50dacc8316c38b3cd98a7d7917b1f9421a405ea4";
    }
}
