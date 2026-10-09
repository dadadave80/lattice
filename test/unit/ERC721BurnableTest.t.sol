// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC721Burnable} from "@lattice-script/base/tokens/DeployERC721Burnable.s.sol";
import {ERC721TestBase} from "@lattice-test/base/ERC721TestBase.sol";
import {ERC721TestFacet} from "@lattice-test/helpers/ERC721TestFacet.sol";
import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";
import {IERC721Burnable} from "@lattice/interfaces/tokens/IERC721Burnable.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";

/// @title ERC721BurnableTest
/// @notice Exercises the {ERC721Burnable} facet through a REAL diamond assembled by the ready-to-deploy
///         {DeployERC721Burnable} recipe (base ERC-721 + the additive burn facet), with the test-only
///         {ERC721TestFacet} cut on top for minting. `burn` runs OpenZeppelin's `_update(address(0), id, caller)`,
///         so only the owner, the token's approved address or an operator can burn.
contract ERC721BurnableTest is ERC721TestBase {
    IERC721Burnable internal burnable;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    uint256 constant TOKEN_1 = 1;
    uint256 constant TOKEN_2 = 2;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function setUp() public override {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            new DeployERC721Burnable().buildCuts("Burnable NFT", "BNFT");
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC721(diamond);
        helper = ERC721TestFacet(diamond);
        burnable = IERC721Burnable(diamond);

        helper.mint(alice, TOKEN_1);
        helper.mint(alice, TOKEN_2);
    }

    function test_SupportsInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC721Burnable).interfaceId), "IERC721Burnable");
        assertEq(type(IERC721Burnable).interfaceId, bytes4(0x42966c68), "IERC721Burnable id");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x80ac58cd), "EIP-721 still registered");
    }

    function test_OwnerBurns() public {
        vm.expectEmit(true, true, true, true, diamond);
        emit Transfer(alice, address(0), TOKEN_1);
        vm.prank(alice);
        burnable.burn(TOKEN_1);

        assertEq(token.balanceOf(alice), 1, "balance decremented");
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, TOKEN_1));
        token.ownerOf(TOKEN_1);
    }

    function test_ApprovedAddressBurns_AndApprovalIsCleared() public {
        vm.prank(alice);
        token.approve(bob, TOKEN_1);

        vm.prank(bob);
        burnable.burn(TOKEN_1);

        assertEq(token.balanceOf(alice), 1, "balance decremented");
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, TOKEN_1));
        token.getApproved(TOKEN_1);
    }

    function test_OperatorBurns() public {
        vm.prank(alice);
        token.setApprovalForAll(bob, true);

        vm.prank(bob);
        burnable.burn(TOKEN_2);

        assertEq(token.balanceOf(alice), 1, "balance decremented");
    }

    function test_StrangerCannotBurn() public {
        vm.prank(charlie);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InsufficientApproval.selector, charlie, TOKEN_1));
        burnable.burn(TOKEN_1);
    }

    function test_BurnNonexistentReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, uint256(99)));
        burnable.burn(99);
    }

    function test_BurnTwiceReverts() public {
        vm.prank(alice);
        burnable.burn(TOKEN_1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, TOKEN_1));
        burnable.burn(TOKEN_1);
    }

    /// @notice A burned id can be minted again, as in OpenZeppelin (ERC-721 does not forbid reuse).
    function test_BurnedIdCanBeReminted() public {
        vm.prank(alice);
        burnable.burn(TOKEN_1);

        helper.mint(bob, TOKEN_1);
        assertEq(token.ownerOf(TOKEN_1), bob, "reminted");
    }

    /// @notice Any caller holding authority over `tokenId` can burn it, and nobody else can.
    function testFuzz_OnlyAuthorizedCallerBurns(address caller) public {
        vm.assume(caller != alice && caller != address(0));
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InsufficientApproval.selector, caller, TOKEN_1));
        burnable.burn(TOKEN_1);

        vm.prank(alice);
        token.approve(caller, TOKEN_1);
        vm.prank(caller);
        burnable.burn(TOKEN_1);
        assertEq(token.balanceOf(alice), 1, "authorized burn");
    }
}
