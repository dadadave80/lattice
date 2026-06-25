// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IERC2981} from "@lattice/interfaces/IERC2981.sol";
import {IMarketplaceZone} from "@lattice/interfaces/IMarketplaceZone.sol";
import {
    ItemType,
    ReceivedItem,
    Schema,
    SpentItem,
    ZoneParameters
} from "@lattice/interfaces/external/SeaportStructs.sol";
import {ZoneInterface} from "@lattice/interfaces/external/ZoneInterface.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.MarketplaceZone")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant MARKETPLACE_ZONE_STORAGE_SLOT = 0xe77b1be4866c120f9cf1b3ac35bdd606adb1b331ef4d920e5a5993f90d992800;

/// @dev ERC-165 map slot for the Seaport `ZoneInterface` (`type(ZoneInterface).interfaceId == 0x3822a094`,
///      the XOR of `authorizeOrder` ^ `validateOrder` ^ `getSeaportMetadata`).
///      `keccak256(abi.encode(bytes4(0x3822a094), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ZONEINTERFACE_SLOT = 0xeb1ff41651f419b216c82171945cb548e85f1f021f4de7ac580f5665f8fc8360;

/// @dev Role that blocks an address from being an order's offerer or fulfiller. `keccak256("MARKETPLACE_BLOCKED_ROLE")`.
bytes32 constant MARKETPLACE_BLOCKED_ROLE = 0xd5b38888b4edc1134d8739971cefa9e01411399342f20f1e31d77b6c38c6ca9b;

/// @notice ERC-7201 namespaced storage for the marketplace zone.
/// @custom:storage-location erc7201:lattice.storage.MarketplaceZone
struct MarketplaceZoneStorage {
    /// @notice Global kill-switch; when true, no order is authorized. APPEND-ONLY.
    bool _paused;
    /// @notice Per-collection ERC-2981 royalty enforcement opt-in. APPEND-ONLY.
    mapping(address collection => bool required) _royaltyRequired;
}

/// @title MarketplaceZoneLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic + ERC-7201 storage for the Seaport `MarketplaceZone` facet. `authorizeOrder` (pre-fulfillment)
///         enforces the pause + offerer/fulfiller blocklist; `validateOrder` (post-fulfillment) enforces that
///         opt-in collections receive their ERC-2981 royalty in the order's consideration. Each returns its
///         own selector as Seaport's magic value, else reverts (Seaport then rejects the order).
/// @dev v1 royalty enforcement assumes a single fungible payment currency per order: `salePrice` is the sum of
///      the fungible consideration the zone sees (never an externally-supplied value), and `royaltyInfo` is
///      consulted best-effort (a non-ERC-2981 token whose `royaltyInfo` reverts is not enforceable → skipped).
library MarketplaceZoneLib {
    function marketplaceZoneStorage() internal pure returns (MarketplaceZoneStorage storage $) {
        assembly {
            $.slot := MARKETPLACE_ZONE_STORAGE_SLOT
        }
    }

    /// @notice Registers the Seaport `ZoneInterface` ERC-165 id.
    function __MarketplaceZone_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for `ZoneInterface` (OpenSea zone introspection).
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ZONEINTERFACE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function zonePaused() internal view returns (bool) {
        return marketplaceZoneStorage()._paused;
    }

    function isRoyaltyRequired(address collection) internal view returns (bool) {
        return marketplaceZoneStorage()._royaltyRequired[collection];
    }

    function blockedRole() internal pure returns (bytes32) {
        return MARKETPLACE_BLOCKED_ROLE;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function setPaused(bool paused_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        marketplaceZoneStorage()._paused = paused_;
        emit IMarketplaceZone.SetPaused(paused_);
    }

    function setRoyaltyRequired(address collection, bool required) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        marketplaceZoneStorage()._royaltyRequired[collection] = required;
        emit IMarketplaceZone.SetRoyaltyRequired(collection, required);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               SEAPORT ZONE HOOKS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Pre-fulfillment hook: enforce pause + blocklist, then authorize. Reverting here lets Seaport
    ///         skip the order in `fulfillAvailable*` (a non-magic return would revert the whole tx instead).
    function authorizeOrder(ZoneParameters calldata zoneParameters) internal view returns (bytes4) {
        _checkGate(zoneParameters.offerer, zoneParameters.fulfiller);
        return ZoneInterface.authorizeOrder.selector;
    }

    /// @notice Post-fulfillment hook: enforce per-collection ERC-2981 royalties (v1: single-NFT ask listings;
    ///         see {_enforceRoyalties}), then validate. View-only policy — harmless if called by a non-Seaport
    ///         caller (no state changes; the returned magic value only matters to Seaport itself).
    function validateOrder(ZoneParameters calldata zoneParameters) internal view returns (bytes4) {
        _enforceRoyalties(zoneParameters);
        return ZoneInterface.validateOrder.selector;
    }

    /// @notice SIP introspection.
    function getSeaportMetadata() internal pure returns (string memory name, Schema[] memory schemas) {
        return ("LatticeMarketplaceZone", new Schema[](0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Reverts if paused or if either party is on the blocklist.
    function _checkGate(address offerer, address fulfiller) private view {
        if (marketplaceZoneStorage()._paused) revert IMarketplaceZone.ZonePaused();
        if (AccessControlLib.hasRole(MARKETPLACE_BLOCKED_ROLE, offerer)) {
            revert IMarketplaceZone.BlockedParticipant(offerer);
        }
        if (AccessControlLib.hasRole(MARKETPLACE_BLOCKED_ROLE, fulfiller)) {
            revert IMarketplaceZone.BlockedParticipant(fulfiller);
        }
    }

    /// @notice v1 royalty enforcement: for a single opted-in NFT sold as an ASK listing in one fungible
    ///         currency, require the consideration to pay >= `royaltyInfo(tokenId, salePrice)` to the 2981
    ///         receiver. To never silently bypass, every case v1 cannot cleanly decide REVERTS: an opted-in
    ///         NFT on the consideration (bid) side, a multi-NFT bundle, a zero fungible price, or an opted-in
    ///         collection whose `royaltyInfo` reverts. `salePrice` is the gross fungible consideration the
    ///         zone sees (offerer-controlled, never an external input) — including fees, so the floor is
    ///         conservative (favors the creator), never understated.
    function _enforceRoyalties(ZoneParameters calldata zp) private view {
        MarketplaceZoneStorage storage $ = marketplaceZoneStorage();

        // An opted-in NFT on the consideration (bid) side is not enforceable in v1 → reject, don't bypass.
        uint256 considerationLen = zp.consideration.length;
        for (uint256 i; i < considerationLen; ++i) {
            ReceivedItem calldata c = zp.consideration[i];
            if (_isNFT(c.itemType) && $._royaltyRequired[c.token]) revert IMarketplaceZone.BidOrdersUnsupported();
        }

        // Locate the single opted-in NFT on the offer (ask) side; bundles are rejected.
        address nftToken;
        uint256 nftId;
        uint256 count;
        uint256 offerLen = zp.offer.length;
        for (uint256 i; i < offerLen; ++i) {
            SpentItem calldata it = zp.offer[i];
            if (_isNFT(it.itemType) && $._royaltyRequired[it.token]) {
                if (++count > 1) revert IMarketplaceZone.BundleOrdersUnsupported();
                nftToken = it.token;
                nftId = it.identifier;
            }
        }
        if (count == 0) return; // nothing opted-in

        (ItemType curType, address curToken, uint256 salePrice) = _saleCurrency(zp.consideration);
        if (salePrice == 0) revert IMarketplaceZone.ZeroPriceRoyaltyOrder();

        (address receiver, uint256 royaltyAmount) = _royaltyInfo(nftToken, nftId, salePrice);
        if (royaltyAmount == 0) return; // no royalty owed at this price

        uint256 paid;
        for (uint256 j; j < considerationLen; ++j) {
            ReceivedItem calldata c = zp.consideration[j];
            if (c.itemType == curType && c.token == curToken && c.recipient == receiver) paid += c.amount;
        }
        if (paid < royaltyAmount) {
            revert IMarketplaceZone.MissingRoyalty(nftToken, nftId, receiver, royaltyAmount, paid);
        }
    }

    /// @notice Queries ERC-2981 `royaltyInfo`. A revert on an opted-in collection is a HARD failure
    ///         ({RoyaltyInfoUnavailable}) — the order is rejected, never allowed royalty-free.
    function _royaltyInfo(address token, uint256 tokenId, uint256 salePrice)
        private
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        try IERC2981(token).royaltyInfo(tokenId, salePrice) returns (address r, uint256 a) {
            return (r, a);
        } catch {
            revert IMarketplaceZone.RoyaltyInfoUnavailable(token);
        }
    }

    /// @notice Sums the fungible consideration into `salePrice`, requiring a single currency. Reverts
    ///         {MixedPaymentCurrency} if two distinct fungible currencies appear (v1 limitation).
    function _saleCurrency(ReceivedItem[] calldata consideration)
        private
        pure
        returns (ItemType curType, address curToken, uint256 salePrice)
    {
        bool set;
        uint256 len = consideration.length;
        for (uint256 i; i < len; ++i) {
            ReceivedItem calldata c = consideration[i];
            if (!_isFungible(c.itemType)) continue;
            if (!set) {
                curType = c.itemType;
                curToken = c.token;
                set = true;
            } else if (c.itemType != curType || c.token != curToken) {
                revert IMarketplaceZone.MixedPaymentCurrency();
            }
            salePrice += c.amount;
        }
    }

    function _isNFT(ItemType t) private pure returns (bool) {
        return uint8(t) >= uint8(ItemType.ERC721); // ERC721(2) .. ERC1155_WITH_CRITERIA(5)
    }

    function _isFungible(ItemType t) private pure returns (bool) {
        return uint8(t) <= uint8(ItemType.ERC20); // NATIVE(0), ERC20(1)
    }
}
