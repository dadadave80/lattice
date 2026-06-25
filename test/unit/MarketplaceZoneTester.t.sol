// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IMarketplaceZone} from "@lattice/interfaces/IMarketplaceZone.sol";
import {
    ItemType,
    ReceivedItem,
    Schema,
    SpentItem,
    ZoneParameters
} from "@lattice/interfaces/external/SeaportStructs.sol";
import {ZoneInterface} from "@lattice/interfaces/external/ZoneInterface.sol";
import {MarketplaceZone} from "@lattice/markets/MarketplaceZone.sol";
import {MARKETPLACE_BLOCKED_ROLE, MarketplaceZoneLib} from "@lattice/markets/libraries/MarketplaceZoneLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal ERC-2981 NFT: royaltyInfo returns `salePrice * bps / 10000` to `receiver`.
contract MockERC2981 {
    address public receiver;
    uint96 public bps;

    constructor(address receiver_, uint96 bps_) {
        receiver = receiver_;
        bps = bps_;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view returns (address, uint256) {
        return (receiver, (salePrice * bps) / 10_000);
    }

    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x2a55205a || id == 0x01ffc9a7;
    }
}

contract MockMarketplaceZone is AccessControl, MarketplaceZone {
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

contract MarketplaceZoneTester is Test {
    MockMarketplaceZone zone;
    MockERC2981 nft;

    address admin = address(0x1);
    address seller = address(0x2);
    address buyer = address(0x3);
    address royaltyRecv = address(0x4);
    address currency = address(0xC0FFEE); // ERC20 payment currency (struct-only; never called)
    address currency2 = address(0xDECAF);

    uint256 constant TOKEN_ID = 42;
    uint96 constant BPS = 500; // 5%

    bytes4 constant AUTHORIZE_MAGIC = 0x01e4d72a;
    bytes4 constant VALIDATE_MAGIC = 0x17b1f942;
    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        zone = new MockMarketplaceZone();
        zone.initialize(admin);
        nft = new MockERC2981(royaltyRecv, BPS);
    }

    // -------- builders --------

    function _offer() internal view returns (SpentItem[] memory o) {
        o = new SpentItem[](1);
        o[0] = SpentItem({itemType: ItemType.ERC721, token: address(nft), identifier: TOKEN_ID, amount: 1});
    }

    function _recv(address token, uint256 amount, address to) internal pure returns (ReceivedItem memory) {
        return
            ReceivedItem({
                itemType: ItemType.ERC20, token: token, identifier: 0, amount: amount, recipient: payable(to)
            });
    }

    function _zp(address offerer_, address fulfiller_, SpentItem[] memory offer_, ReceivedItem[] memory cons_)
        internal
        pure
        returns (ZoneParameters memory)
    {
        return ZoneParameters({
            orderHash: bytes32(0),
            fulfiller: fulfiller_,
            offerer: offerer_,
            offer: offer_,
            consideration: cons_,
            extraData: "",
            orderHashes: new bytes32[](0),
            startTime: 0,
            endTime: 0,
            zoneHash: bytes32(0)
        });
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsInterfaceZone() public view {
        assertEq(type(ZoneInterface).interfaceId, bytes4(0x3822a094));
        assertTrue(zone.supportsInterface(type(ZoneInterface).interfaceId));
    }

    function test_GetSeaportMetadata() public view {
        (string memory name, Schema[] memory schemas) = zone.getSeaportMetadata();
        assertEq(name, "LatticeMarketplaceZone");
        assertEq(schemas.length, 0);
    }

    function test_BlockedRole() public view {
        assertEq(zone.blockedRole(), MARKETPLACE_BLOCKED_ROLE);
    }

    function test_SetPaused() public {
        assertFalse(zone.zonePaused());
        vm.prank(admin);
        zone.setPaused(true);
        assertTrue(zone.zonePaused());
    }

    function test_SetPausedRevertsNonAdmin() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, buyer, bytes32(0)));
        zone.setPaused(true);
    }

    function test_SetRoyaltyRequired() public {
        assertFalse(zone.isRoyaltyRequired(address(nft)));
        vm.prank(admin);
        zone.setRoyaltyRequired(address(nft), true);
        assertTrue(zone.isRoyaltyRequired(address(nft)));
    }

    function test_SetRoyaltyRequiredRevertsNonAdmin() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, buyer, bytes32(0)));
        zone.setRoyaltyRequired(address(nft), true);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          AUTHORIZE (pause + blocklist)
    //////////////////////////////////////////////////////////////////////////*//

    function _basicOrder() internal view returns (ZoneParameters memory) {
        ReceivedItem[] memory cons = new ReceivedItem[](1);
        cons[0] = _recv(currency, 100 ether, seller);
        return _zp(seller, buyer, _offer(), cons);
    }

    function test_AuthorizeOrderReturnsMagic() public {
        assertEq(zone.authorizeOrder(_basicOrder()), AUTHORIZE_MAGIC);
    }

    function test_AuthorizeOrderPausedReverts() public {
        vm.prank(admin);
        zone.setPaused(true);
        vm.expectRevert(IMarketplaceZone.ZonePaused.selector);
        zone.authorizeOrder(_basicOrder());
    }

    function test_AuthorizeOrderBlockedOffererReverts() public {
        vm.prank(admin);
        zone.grantRole(MARKETPLACE_BLOCKED_ROLE, seller);
        vm.expectRevert(abi.encodeWithSelector(IMarketplaceZone.BlockedParticipant.selector, seller));
        zone.authorizeOrder(_basicOrder());
    }

    function test_AuthorizeOrderBlockedFulfillerReverts() public {
        vm.prank(admin);
        zone.grantRole(MARKETPLACE_BLOCKED_ROLE, buyer);
        vm.expectRevert(abi.encodeWithSelector(IMarketplaceZone.BlockedParticipant.selector, buyer));
        zone.authorizeOrder(_basicOrder());
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          VALIDATE (ERC-2981 royalty)
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev sale of 100 ether: seller gets `sellerAmt`, `royaltyRecv` gets `royaltyAmt`. salePrice = sum.
    function _saleOrder(uint256 sellerAmt, uint256 royaltyAmt) internal view returns (ZoneParameters memory) {
        ReceivedItem[] memory cons = new ReceivedItem[](royaltyAmt > 0 ? 2 : 1);
        cons[0] = _recv(currency, sellerAmt, seller);
        if (royaltyAmt > 0) cons[1] = _recv(currency, royaltyAmt, royaltyRecv);
        return _zp(seller, buyer, _offer(), cons);
    }

    function test_ValidateOrderNotRequiredReturnsMagic() public {
        // collection not flagged → no royalty check even if absent
        assertEq(zone.validateOrder(_saleOrder(100 ether, 0)), VALIDATE_MAGIC);
    }

    function test_ValidateOrderRoyaltyPresentReturnsMagic() public {
        vm.prank(admin);
        zone.setRoyaltyRequired(address(nft), true);
        // salePrice = 95 + 5 = 100; royaltyInfo(.,100) = 5% = 5 ether to royaltyRecv; present → ok
        assertEq(zone.validateOrder(_saleOrder(95 ether, 5 ether)), VALIDATE_MAGIC);
    }

    function test_ValidateOrderMissingRoyaltyReverts() public {
        vm.prank(admin);
        zone.setRoyaltyRequired(address(nft), true);
        // no royalty item: salePrice = 100; required = 5 ether; provided = 0
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketplaceZone.MissingRoyalty.selector, address(nft), TOKEN_ID, royaltyRecv, 5 ether, 0
            )
        );
        zone.validateOrder(_saleOrder(100 ether, 0));
    }

    function test_ValidateOrderInsufficientRoyaltyReverts() public {
        vm.prank(admin);
        zone.setRoyaltyRequired(address(nft), true);
        // salePrice = 97 + 3 = 100; required = 5 ether; provided = 3 ether
        vm.expectRevert(
            abi.encodeWithSelector(
                IMarketplaceZone.MissingRoyalty.selector, address(nft), TOKEN_ID, royaltyRecv, 5 ether, 3 ether
            )
        );
        zone.validateOrder(_saleOrder(97 ether, 3 ether));
    }

    function test_ValidateOrderMixedCurrencyReverts() public {
        vm.prank(admin);
        zone.setRoyaltyRequired(address(nft), true);
        ReceivedItem[] memory cons = new ReceivedItem[](2);
        cons[0] = _recv(currency, 95 ether, seller);
        cons[1] = _recv(currency2, 5 ether, royaltyRecv); // different currency
        vm.expectRevert(IMarketplaceZone.MixedPaymentCurrency.selector);
        zone.validateOrder(_zp(seller, buyer, _offer(), cons));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    VALIDATE — unenforceable cases are REJECTED
    //////////////////////////////////////////////////////////////////////////*//

    function test_ValidateOrderBidReverts() public {
        // opted-in NFT on the consideration (bid) side → rejected, not bypassed
        vm.prank(admin);
        zone.setRoyaltyRequired(address(nft), true);
        SpentItem[] memory offer = new SpentItem[](1);
        offer[0] = SpentItem({itemType: ItemType.ERC20, token: currency, identifier: 0, amount: 100 ether});
        ReceivedItem[] memory cons = new ReceivedItem[](1);
        cons[0] = ReceivedItem({
            itemType: ItemType.ERC721, token: address(nft), identifier: TOKEN_ID, amount: 1, recipient: payable(buyer)
        });
        vm.expectRevert(IMarketplaceZone.BidOrdersUnsupported.selector);
        zone.validateOrder(_zp(buyer, seller, offer, cons));
    }

    function test_ValidateOrderBundleReverts() public {
        vm.prank(admin);
        zone.setRoyaltyRequired(address(nft), true);
        SpentItem[] memory offer = new SpentItem[](2);
        offer[0] = SpentItem({itemType: ItemType.ERC721, token: address(nft), identifier: TOKEN_ID, amount: 1});
        offer[1] = SpentItem({itemType: ItemType.ERC721, token: address(nft), identifier: TOKEN_ID + 1, amount: 1});
        ReceivedItem[] memory cons = new ReceivedItem[](1);
        cons[0] = _recv(currency, 100 ether, seller);
        vm.expectRevert(IMarketplaceZone.BundleOrdersUnsupported.selector);
        zone.validateOrder(_zp(seller, buyer, offer, cons));
    }

    function test_ValidateOrderZeroPriceReverts() public {
        vm.prank(admin);
        zone.setRoyaltyRequired(address(nft), true);
        // opted-in NFT, no fungible consideration → salePrice 0 → reject (no royalty-free barter)
        vm.expectRevert(IMarketplaceZone.ZeroPriceRoyaltyOrder.selector);
        zone.validateOrder(_zp(seller, buyer, _offer(), new ReceivedItem[](0)));
    }

    function test_ValidateOrderNon2981Reverts() public {
        // a collection opted-in but whose royaltyInfo reverts is a HARD failure, not a silent skip
        MockNon2981 bad = new MockNon2981();
        vm.prank(admin);
        zone.setRoyaltyRequired(address(bad), true);
        SpentItem[] memory offer = new SpentItem[](1);
        offer[0] = SpentItem({itemType: ItemType.ERC721, token: address(bad), identifier: 1, amount: 1});
        ReceivedItem[] memory cons = new ReceivedItem[](1);
        cons[0] = _recv(currency, 100 ether, seller);
        vm.expectRevert(abi.encodeWithSelector(IMarketplaceZone.RoyaltyInfoUnavailable.selector, address(bad)));
        zone.validateOrder(_zp(seller, buyer, offer, cons));
    }
}

/// @notice A contract with no `royaltyInfo` — calling it reverts (used to test the hard-fail path).
contract MockNon2981 {}
