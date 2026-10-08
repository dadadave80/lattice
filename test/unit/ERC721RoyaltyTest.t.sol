// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC721Royalty} from "@lattice-script/base/tokens/DeployERC721Royalty.s.sol";
import {ERC721TestBase} from "@lattice-test/base/ERC721TestBase.sol";
import {ERC721TestFacet} from "@lattice-test/helpers/ERC721TestFacet.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";
import {IERC721Burnable} from "@lattice/interfaces/tokens/IERC721Burnable.sol";
import {ERC2981} from "@lattice/tokens/ERC2981/ERC2981.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721Burnable} from "@lattice/tokens/ERC721/ERC721Burnable.sol";
import {ERC721BurnableInit} from "@lattice/tokens/ERC721/ERC721BurnableInit.sol";

/// @title ERC721RoyaltyTest
/// @notice The OpenZeppelin `ERC721Royalty` equivalent: a REAL diamond from {DeployERC721Royalty} that cuts the base
///         {ERC721} and {ERC2981} facets side by side. OpenZeppelin v5.6.1's `ERC721Royalty` only merges
///         `supportsInterface`, and v5 stopped resetting royalties on burn, so the recipe needs no royalty hook in
///         the token's burn path. The test diamond also cuts the shipped {ERC721Burnable} facet (OpenZeppelin's
///         `ERC721Royalty` does not include burning, so the recipe does not), so the burned-id case goes through
///         the production burn path. The test-only {ERC721TestFacet} supplies mint.
contract ERC721RoyaltyTest is ERC721TestBase {
    ERC2981 internal royalty;

    address admin = address(0xA11CE);
    address alice = address(0x1);
    address receiver = address(0xBEEF);
    address tokenReceiver = address(0xCAFE);

    uint256 constant TOKEN_1 = 1;
    uint256 constant SALE_PRICE = 10_000;

    function setUp() public override {
        (FacetCut[] memory recipeCuts, address[] memory recipeInits, bytes[] memory recipeCalldatas) =
            new DeployERC721Royalty().buildCuts("Royalty NFT", "RNFT", admin);

        FacetCut[] memory cuts = new FacetCut[](recipeCuts.length + 1);
        for (uint256 i; i < recipeCuts.length; ++i) {
            cuts[i] = recipeCuts[i];
        }
        bytes4[] memory burnSelectors = new bytes4[](1);
        burnSelectors[0] = IERC721Burnable.burn.selector;
        cuts[recipeCuts.length] = FacetCut({
            facetAddress: address(new ERC721Burnable()), action: FacetCutAction.Add, functionSelectors: burnSelectors
        });

        address[] memory inits = new address[](recipeInits.length + 1);
        bytes[] memory initCalldatas = new bytes[](recipeInits.length + 1);
        for (uint256 i; i < recipeInits.length; ++i) {
            inits[i] = recipeInits[i];
            initCalldatas[i] = recipeCalldatas[i];
        }
        inits[recipeInits.length] = address(new ERC721BurnableInit());
        initCalldatas[recipeInits.length] = abi.encodeCall(ERC721BurnableInit.init, ());

        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC721(diamond);
        helper = ERC721TestFacet(diamond);
        royalty = ERC2981(diamond);

        helper.mint(alice, TOKEN_1);
    }

    function test_SupportsInterface() public view {
        ERC165Facet introspection = ERC165Facet(diamond);
        assertTrue(introspection.supportsInterface(0x80ac58cd), "EIP-721");
        assertTrue(introspection.supportsInterface(0x5b5e139f), "EIP-721 metadata");
        assertTrue(introspection.supportsInterface(0x2a55205a), "EIP-2981");
        assertTrue(introspection.supportsInterface(0x01ffc9a7), "EIP-165");
    }

    function test_NameAndSymbol() public view {
        assertEq(token.name(), "Royalty NFT");
        assertEq(token.symbol(), "RNFT");
    }

    function test_DefaultRoyaltyForMintedToken() public {
        vm.prank(admin);
        royalty.setDefaultRoyalty(receiver, 500);

        (address to, uint256 amount) = royalty.royaltyInfo(TOKEN_1, SALE_PRICE);
        assertEq(to, receiver, "default receiver");
        assertEq(amount, 500, "5% of 10_000");
    }

    function test_TokenRoyaltyOverridesDefault() public {
        vm.startPrank(admin);
        royalty.setDefaultRoyalty(receiver, 500);
        royalty.setTokenRoyalty(TOKEN_1, tokenReceiver, 1000);
        vm.stopPrank();

        (address to, uint256 amount) = royalty.royaltyInfo(TOKEN_1, SALE_PRICE);
        assertEq(to, tokenReceiver, "token receiver");
        assertEq(amount, 1000, "10% of 10_000");
    }

    /// @notice OpenZeppelin v5 dropped the burn-time royalty reset ("Stop resetting token-specific URI and
    ///         royalties when burning"), so `royaltyInfo` keeps answering for an id burned through
    ///         {ERC721Burnable}, and a re-mint of the same id inherits the old per-token royalty.
    function test_RoyaltyInfoForBurnedTokenIsUnchanged() public {
        vm.prank(admin);
        royalty.setTokenRoyalty(TOKEN_1, tokenReceiver, 1000);

        vm.prank(alice);
        IERC721Burnable(diamond).burn(TOKEN_1);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, TOKEN_1));
        token.ownerOf(TOKEN_1);

        (address to, uint256 amount) = royalty.royaltyInfo(TOKEN_1, SALE_PRICE);
        assertEq(to, tokenReceiver, "per-token royalty survives burn");
        assertEq(amount, 1000, "amount survives burn");
    }

    function test_RoyaltySettersAreAdminGated() public {
        bytes32 adminRole = 0x00;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, adminRole)
        );
        royalty.setDefaultRoyalty(receiver, 500);
    }
}
