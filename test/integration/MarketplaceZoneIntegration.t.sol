// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IMarketplaceZone} from "@lattice/interfaces/IMarketplaceZone.sol";
import {ItemType, ReceivedItem, SpentItem, ZoneParameters} from "@lattice/interfaces/external/SeaportStructs.sol";
import {ZoneInterface} from "@lattice/interfaces/external/ZoneInterface.sol";
import {MarketplaceZone} from "@lattice/markets/MarketplaceZone.sol";
import {MARKETPLACE_BLOCKED_ROLE, MarketplaceZoneLib} from "@lattice/markets/libraries/MarketplaceZoneLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal ERC-2981 NFT.
contract MockERC2981 {
    function royaltyInfo(uint256, uint256 salePrice) external view returns (address, uint256) {
        return (RECEIVER, (salePrice * 500) / 10_000); // 5%
    }

    address constant RECEIVER = address(0x4);
}

/// @notice A faithful stand-in for Seaport's restricted-order flow, replicating `seaport-core`
///         `ZoneInteraction`: call `authorizeOrder` BEFORE transfers, then (transfers), then `validateOrder`
///         AFTER transfers, reverting `InvalidRestrictedOrder` if either returns the wrong magic value. Any
///         revert thrown by the zone propagates and aborts the whole fulfillment (as on the real Seaport).
contract MockSeaport {
    error InvalidRestrictedOrder(bytes32 orderHash);

    bool public fulfilled;

    function fulfillRestricted(address zone, ZoneParameters calldata zp) external {
        if (ZoneInterface(zone).authorizeOrder(zp) != ZoneInterface.authorizeOrder.selector) {
            revert InvalidRestrictedOrder(zp.orderHash);
        }
        // (Seaport executes all token transfers here, between the two hooks.)
        if (ZoneInterface(zone).validateOrder(zp) != ZoneInterface.validateOrder.selector) {
            revert InvalidRestrictedOrder(zp.orderHash);
        }
        fulfilled = true;
    }
}

contract Zone is AccessControl, MarketplaceZone {
    function initialize(address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        MarketplaceZoneLib.__MarketplaceZone_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

/// @title MarketplaceZoneIntegration
/// @notice End-to-end: a Seaport-faithful caller sequences `authorizeOrder` → transfers → `validateOrder`
///         against the live zone facet, asserting an order fulfills only when pause/blocklist/royalty policy
///         holds and the whole fulfillment aborts (zone revert propagates) otherwise.
contract MarketplaceZoneIntegration is Test {
    Zone zone;
    MockSeaport seaport;
    MockERC2981 nft;

    address admin = address(0x1);
    address seller = address(0x2);
    address buyer = address(0x3);
    address royaltyRecv = address(0x4);
    address currency = address(0xC0FFEE);

    function setUp() public {
        zone = new Zone();
        zone.initialize(admin);
        seaport = new MockSeaport();
        nft = new MockERC2981();
    }

    function _order(uint256 sellerAmt, uint256 royaltyAmt) internal view returns (ZoneParameters memory) {
        SpentItem[] memory offer = new SpentItem[](1);
        offer[0] = SpentItem({itemType: ItemType.ERC721, token: address(nft), identifier: 7, amount: 1});
        ReceivedItem[] memory cons = new ReceivedItem[](royaltyAmt > 0 ? 2 : 1);
        cons[0] = ReceivedItem({
            itemType: ItemType.ERC20, token: currency, identifier: 0, amount: sellerAmt, recipient: payable(seller)
        });
        if (royaltyAmt > 0) {
            cons[1] = ReceivedItem({
                itemType: ItemType.ERC20,
                token: currency,
                identifier: 0,
                amount: royaltyAmt,
                recipient: payable(royaltyRecv)
            });
        }
        return ZoneParameters({
            orderHash: keccak256("order"),
            fulfiller: buyer,
            offerer: seller,
            offer: offer,
            consideration: cons,
            extraData: "",
            orderHashes: new bytes32[](0),
            startTime: 0,
            endTime: 0,
            zoneHash: bytes32(0)
        });
    }

    function test_Integration_FulfillsWhenPolicyPasses() public {
        vm.prank(admin);
        zone.setRoyaltyRequired(address(nft), true);
        // salePrice 100; 5% royalty = 5 present
        seaport.fulfillRestricted(address(zone), _order(95 ether, 5 ether));
        assertTrue(seaport.fulfilled());
    }

    function test_Integration_RevertsWhenPaused() public {
        vm.prank(admin);
        zone.setPaused(true);
        vm.expectRevert(IMarketplaceZone.ZonePaused.selector);
        seaport.fulfillRestricted(address(zone), _order(100 ether, 0));
        assertFalse(seaport.fulfilled());
    }

    function test_Integration_RevertsWhenOffererBlocked() public {
        vm.prank(admin);
        zone.grantRole(MARKETPLACE_BLOCKED_ROLE, seller);
        vm.expectRevert(abi.encodeWithSelector(IMarketplaceZone.BlockedParticipant.selector, seller));
        seaport.fulfillRestricted(address(zone), _order(100 ether, 0));
    }

    function test_Integration_RevertsWhenRoyaltyMissing() public {
        vm.prank(admin);
        zone.setRoyaltyRequired(address(nft), true);
        // royalty enforced post-"transfer" in validateOrder: required 5, provided 0
        vm.expectRevert(
            abi.encodeWithSelector(IMarketplaceZone.MissingRoyalty.selector, address(nft), 7, royaltyRecv, 5 ether, 0)
        );
        seaport.fulfillRestricted(address(zone), _order(100 ether, 0));
        assertFalse(seaport.fulfilled());
    }
}
