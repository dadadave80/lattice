// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC721Enumerable} from "@lattice-script/base/tokens/DeployERC721Enumerable.s.sol";
import {ERC721TestBase} from "@lattice-test/base/ERC721TestBase.sol";
import {ERC721TestFacet} from "@lattice-test/helpers/ERC721TestFacet.sol";
import {IERC721, IERC721Receiver} from "@lattice/interfaces/tokens/IERC721.sol";
import {IERC721Enumerable} from "@lattice/interfaces/tokens/IERC721Enumerable.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";

/// @dev Accepts every safe transfer.
contract EnumerableReceiver is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

/// @dev Has code but no `onERC721Received`, so a safe transfer to it reverts with empty data.
contract EnumerableNonReceiver {}

/// @title ERC721EnumerableTest
/// @notice Exercises the {ERC721Enumerable} facet through a REAL diamond assembled by the {DeployERC721Enumerable}
///         recipe: base ERC-721 plus the enumeration facet, which adds the three views and REPLACES `transferFrom`
///         and both `safeTransferFrom` overloads. The test-only {ERC721TestFacet} mints and burns through
///         {ERC721EnumerableLib}, as an app facet on an enumerable diamond must. Expected orders follow
///         OpenZeppelin v5.6.1's swap-and-pop.
contract ERC721EnumerableTest is ERC721TestBase {
    IERC721Enumerable internal enumerable;

    address alice = address(0x1);
    address bob = address(0x2);

    function setUp() public override {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            new DeployERC721Enumerable().buildCuts("Enumerable NFT", "ENFT");
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC721(diamond);
        helper = ERC721TestFacet(diamond);
        enumerable = IERC721Enumerable(diamond);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsInterface() public view {
        assertEq(type(IERC721Enumerable).interfaceId, bytes4(0x780e9d63), "canonical EIP-721 enumeration id");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x780e9d63), "IERC721Enumerable");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x80ac58cd), "EIP-721");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x5b5e139f), "EIP-721 metadata");
    }

    /// @notice The recipe routes the three views and all three movement selectors to the enumerable facet.
    function test_RecipeRoutesViewsAndMovementToFacet() public view {
        address facet = IDiamondLoupe(diamond).facetAddress(IERC721Enumerable.totalSupply.selector);
        assertTrue(facet != IDiamondLoupe(diamond).facetAddress(IERC721.approve.selector), "not the base facet");
        assertEq(IDiamondLoupe(diamond).facetAddress(IERC721Enumerable.tokenByIndex.selector), facet);
        assertEq(IDiamondLoupe(diamond).facetAddress(IERC721Enumerable.tokenOfOwnerByIndex.selector), facet);
        assertEq(IDiamondLoupe(diamond).facetAddress(IERC721.transferFrom.selector), facet, "transferFrom");
        assertEq(IDiamondLoupe(diamond).facetAddress(0x42842e0e), facet, "safeTransferFrom(3)");
        assertEq(IDiamondLoupe(diamond).facetAddress(0xb88d4fde), facet, "safeTransferFrom(4)");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    function test_EmptyAtDeploy() public {
        assertEq(enumerable.totalSupply(), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Enumerable.ERC721OutOfBoundsIndex.selector, address(0), 0));
        enumerable.tokenByIndex(0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Enumerable.ERC721OutOfBoundsIndex.selector, alice, 0));
        enumerable.tokenOfOwnerByIndex(alice, 0);
    }

    function test_TokenOfOwnerByIndex_ZeroOwnerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidOwner.selector, address(0)));
        enumerable.tokenOfOwnerByIndex(address(0), 0);
    }

    function test_MintListsTokens() public {
        helper.enumerableMint(alice, 10);
        helper.enumerableMint(alice, 20);
        helper.enumerableMint(bob, 30);

        assertEq(enumerable.totalSupply(), 3);
        assertEq(enumerable.tokenByIndex(0), 10);
        assertEq(enumerable.tokenByIndex(1), 20);
        assertEq(enumerable.tokenByIndex(2), 30);
        assertEq(enumerable.tokenOfOwnerByIndex(alice, 0), 10);
        assertEq(enumerable.tokenOfOwnerByIndex(alice, 1), 20);
        assertEq(enumerable.tokenOfOwnerByIndex(bob, 0), 30);

        vm.expectRevert(abi.encodeWithSelector(IERC721Enumerable.ERC721OutOfBoundsIndex.selector, alice, 2));
        enumerable.tokenOfOwnerByIndex(alice, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC721Enumerable.ERC721OutOfBoundsIndex.selector, address(0), 3));
        enumerable.tokenByIndex(3);
    }

    function test_SafeMintListsToken() public {
        address receiver = address(new EnumerableReceiver());
        helper.enumerableSafeMint(receiver, 7);
        assertEq(enumerable.totalSupply(), 1);
        assertEq(enumerable.tokenOfOwnerByIndex(receiver, 0), 7);
    }

    function test_MintExistingIdReverts() public {
        helper.enumerableMint(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidSender.selector, address(0)));
        helper.enumerableMint(bob, 1);
        assertEq(enumerable.totalSupply(), 1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               TRANSFERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Transferring the first of three swaps the last into its slot (OpenZeppelin's swap-and-pop).
    function test_TransferFromMovesBetweenOwnerLists() public {
        helper.enumerableMint(alice, 1);
        helper.enumerableMint(alice, 2);
        helper.enumerableMint(alice, 3);

        vm.prank(alice);
        token.transferFrom(alice, bob, 1);

        assertEq(enumerable.totalSupply(), 3, "a transfer keeps the supply");
        assertEq(token.balanceOf(alice), 2);
        assertEq(enumerable.tokenOfOwnerByIndex(alice, 0), 3, "last id swapped into the vacated slot");
        assertEq(enumerable.tokenOfOwnerByIndex(alice, 1), 2);
        assertEq(enumerable.tokenOfOwnerByIndex(bob, 0), 1);
        assertEq(enumerable.tokenByIndex(0), 1, "the global list is unchanged by a transfer");
    }

    function test_SafeTransferFromBothOverloadsUpdateLists() public {
        helper.enumerableMint(alice, 1);
        helper.enumerableMint(alice, 2);
        address receiver = address(new EnumerableReceiver());

        vm.startPrank(alice);
        token.safeTransferFrom(alice, receiver, 2);
        token.safeTransferFrom(alice, receiver, 1, "data");
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 0);
        assertEq(enumerable.tokenOfOwnerByIndex(receiver, 0), 2);
        assertEq(enumerable.tokenOfOwnerByIndex(receiver, 1), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Enumerable.ERC721OutOfBoundsIndex.selector, alice, 0));
        enumerable.tokenOfOwnerByIndex(alice, 0);
    }

    /// @notice A self-transfer leaves the owner's list untouched (`previousOwner == to`).
    function test_SelfTransferKeepsList() public {
        helper.enumerableMint(alice, 1);
        helper.enumerableMint(alice, 2);
        vm.prank(alice);
        token.transferFrom(alice, alice, 1);
        assertEq(token.balanceOf(alice), 2);
        assertEq(enumerable.tokenOfOwnerByIndex(alice, 0), 1);
        assertEq(enumerable.tokenOfOwnerByIndex(alice, 1), 2);
    }

    function test_TransferFromKeepsBaseChecks() public {
        helper.enumerableMint(alice, 1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InsufficientApproval.selector, bob, 1));
        token.transferFrom(alice, bob, 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidReceiver.selector, address(0)));
        token.transferFrom(alice, address(0), 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721IncorrectOwner.selector, bob, 1, alice));
        token.transferFrom(bob, alice, 1);
    }

    function test_SafeTransferToNonReceiverReverts() public {
        helper.enumerableMint(alice, 1);
        address nonReceiver = address(new EnumerableNonReceiver());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidReceiver.selector, nonReceiver));
        token.safeTransferFrom(alice, nonReceiver, 1);
        assertEq(enumerable.tokenOfOwnerByIndex(alice, 0), 1, "the reverted transfer left the list intact");
    }

    /// @notice The authorization-free {ERC721EnumerableLib._transfer}/{_safeTransfer} (for permissioned or
    ///         signature-based movement) keep both lists in step, as OpenZeppelin's `_update` override does.
    function test_UnauthorizedTransferUpdatesLists() public {
        helper.enumerableMint(alice, 1);
        helper.enumerableMint(alice, 2);
        address receiver = address(new EnumerableReceiver());

        helper.enumerableTransfer(alice, bob, 1);
        helper.enumerableSafeTransfer(alice, receiver, 2);

        assertEq(enumerable.totalSupply(), 2);
        assertEq(token.balanceOf(alice), 0);
        assertEq(enumerable.tokenOfOwnerByIndex(bob, 0), 1);
        assertEq(enumerable.tokenOfOwnerByIndex(receiver, 0), 2);
        vm.expectRevert(abi.encodeWithSelector(IERC721Enumerable.ERC721OutOfBoundsIndex.selector, alice, 0));
        enumerable.tokenOfOwnerByIndex(alice, 0);
    }

    /// @notice The authorization-free transfers keep {ERC721Lib._transfer}'s checks.
    function test_UnauthorizedTransferKeepsBaseChecks() public {
        helper.enumerableMint(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, 9));
        helper.enumerableTransfer(alice, bob, 9);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721IncorrectOwner.selector, bob, 1, alice));
        helper.enumerableTransfer(bob, alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidReceiver.selector, address(0)));
        helper.enumerableTransfer(alice, address(0), 1);

        address nonReceiver = address(new EnumerableNonReceiver());
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidReceiver.selector, nonReceiver));
        helper.enumerableSafeTransfer(alice, nonReceiver, 1);
        assertEq(enumerable.tokenOfOwnerByIndex(alice, 0), 1, "the reverted transfers left the list intact");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 BURN
    //////////////////////////////////////////////////////////////////////////*//

    function test_BurnRemovesFromBothLists() public {
        helper.enumerableMint(alice, 1);
        helper.enumerableMint(alice, 2);
        helper.enumerableMint(bob, 3);

        helper.enumerableBurn(1);

        assertEq(enumerable.totalSupply(), 2);
        assertEq(enumerable.tokenByIndex(0), 3, "the last global id swapped into slot 0");
        assertEq(enumerable.tokenByIndex(1), 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(enumerable.tokenOfOwnerByIndex(alice, 0), 2);
    }

    function test_BurnLastMintedToken() public {
        helper.enumerableMint(alice, 1);
        helper.enumerableMint(alice, 2);
        helper.enumerableBurn(2);
        assertEq(enumerable.totalSupply(), 1);
        assertEq(enumerable.tokenByIndex(0), 1);
        assertEq(enumerable.tokenOfOwnerByIndex(alice, 0), 1);
    }

    function test_BurnNonexistentReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, 9));
        helper.enumerableBurn(9);
    }

    function test_ReMintAfterBurn() public {
        helper.enumerableMint(alice, 1);
        helper.enumerableBurn(1);
        helper.enumerableMint(bob, 1);
        assertEq(enumerable.totalSupply(), 1);
        assertEq(enumerable.tokenByIndex(0), 1);
        assertEq(enumerable.tokenOfOwnerByIndex(bob, 0), 1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  FUZZ
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Minting `n` ids then transferring a subset keeps every owner list and the global list complete.
    function testFuzz_MintThenTransferKeepsListsComplete(uint8 n, uint256 mask) public {
        n = uint8(bound(n, 1, 24));
        for (uint256 i; i < n; ++i) {
            helper.enumerableMint(alice, 100 + i);
        }
        uint256 moved;
        for (uint256 i; i < n; ++i) {
            if ((mask >> i) & 1 == 1) {
                vm.prank(alice);
                token.transferFrom(alice, bob, 100 + i);
                ++moved;
            }
        }
        assertEq(enumerable.totalSupply(), n);
        assertEq(token.balanceOf(bob), moved);
        _assertOwnerListComplete(alice);
        _assertOwnerListComplete(bob);
    }

    /// @dev Every listed id is owned by `owner`, and the list has exactly `balanceOf(owner)` distinct entries.
    function _assertOwnerListComplete(address owner) internal view {
        uint256 balance = token.balanceOf(owner);
        uint256[] memory seen = new uint256[](balance);
        for (uint256 i; i < balance; ++i) {
            uint256 id = enumerable.tokenOfOwnerByIndex(owner, i);
            assertEq(token.ownerOf(id), owner, "listed id owned by the owner");
            for (uint256 j; j < i; ++j) {
                assertTrue(seen[j] != id, "duplicate id in owner list");
            }
            seen[i] = id;
        }
    }
}
