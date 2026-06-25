// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Seaport order structs (vendored subset)
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The minimal Seaport 1.6 enums + structs a {MarketplaceZone} receives in its `authorizeOrder` /
///         `validateOrder` hooks. Per the repo "vendor, don't install" policy, only the zone-facing types are
///         copied — not the full order/fulfillment surface.
/// @dev Verified verbatim against `ProjectOpenSea/seaport-types` @ `b724932` (tag v1.6.3, 2024-03-12):
///      `src/lib/ConsiderationEnums.sol` (ItemType) and `src/lib/ConsiderationStructs.sol`
///      (SpentItem, ReceivedItem, Schema, ZoneParameters). `OrderType` is omitted — it is not a field of
///      `ZoneParameters` (the zone only ever sees the resolved offer/consideration).
/// @custom:lattice-source Seaport

/// @notice MIT — ItemType, in declaration order (NATIVE=0 … ERC1155_WITH_CRITERIA=5).
enum ItemType {
    NATIVE,
    ERC20,
    ERC721,
    ERC1155,
    ERC721_WITH_CRITERIA,
    ERC1155_WITH_CRITERIA
}

/// @notice An item the order gives up (the offer side). For an NFT sale, `token`/`identifier` name the NFT.
struct SpentItem {
    ItemType itemType;
    address token;
    uint256 identifier;
    uint256 amount;
}

/// @notice An item the order pays out (the consideration side), including a `recipient` — this is where
///         payments, fees, and ERC-2981 royalties land.
struct ReceivedItem {
    ItemType itemType;
    address token;
    uint256 identifier;
    uint256 amount;
    address payable recipient;
}

/// @notice SIP metadata schema entry returned by `getSeaportMetadata`.
struct Schema {
    uint256 id;
    bytes metadata;
}

/// @notice The fully-resolved order context Seaport passes to a restricted order's zone. `offer` and
///         `consideration` carry final (post-fraction) amounts at `validateOrder` time.
struct ZoneParameters {
    bytes32 orderHash;
    address fulfiller;
    address offerer;
    SpentItem[] offer;
    ReceivedItem[] consideration;
    bytes extraData;
    bytes32[] orderHashes;
    uint256 startTime;
    uint256 endTime;
    bytes32 zoneHash;
}
