// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ERC721TestBase} from "@lattice-test/base/ERC721TestBase.sol";
import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";

/// @notice ERC721Receiver that correctly returns the expected selector.
contract GoodReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

/// @notice ERC721Receiver that returns the wrong selector.
contract BadReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return bytes4(0);
    }
}

/// @notice ERC721Receiver that deliberately reverts with a custom error.
contract RevertingReceiver {
    error MintNotOpen();

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        revert MintNotOpen();
    }
}

/// @title ERC721Test
/// @notice Exercises the base ERC-721 facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployERC721} script (see {ERC721TestBase}) — every call below routes through the diamond's
///         `delegatecall` dispatch, not a flattened inheritance mock. Internal mint/burn/transfer primitives
///         come from the test-only {ERC721TestFacet} (`helper`); `supportsInterface` from the cut-in
///         `ERC165Facet`.
contract ERC721Test is ERC721TestBase {
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    uint256 constant TOKEN_1 = 1;
    uint256 constant TOKEN_2 = 2;
    uint256 constant TOKEN_3 = 3;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    //*//////////////////////////////////////////////////////////////////////////
    //                               METADATA TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_Name() public view {
        assertEq(token.name(), "Test NFT");
    }

    function test_Symbol() public view {
        assertEq(token.symbol(), "TNFT");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               MINT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintSetsBalanceAndOwner() public {
        helper.mint(alice, TOKEN_1);

        assertEq(token.balanceOf(alice), 1);
        assertEq(token.ownerOf(TOKEN_1), alice);
    }

    function test_MintEmitsTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, TOKEN_1);

        helper.mint(alice, TOKEN_1);
    }

    function test_MintToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidReceiver.selector, address(0)));
        helper.mint(address(0), TOKEN_1);
    }

    function test_MintExistingTokenReverts() public {
        helper.mint(alice, TOKEN_1);

        // Minting same tokenId again: _update returns alice (non-zero), _mint reverts with ERC721InvalidSender
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidSender.selector, alice));
        helper.mint(bob, TOKEN_1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               BALANCE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_BalanceOfReturnsCount() public {
        helper.mint(alice, TOKEN_1);
        helper.mint(alice, TOKEN_2);
        helper.mint(bob, TOKEN_3);

        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(charlie), 0);
    }

    function test_OwnerOfNonexistentReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, uint256(999)));
        token.ownerOf(999);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              TRANSFER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_TransferFromUpdatesOwner() public {
        helper.mint(alice, TOKEN_1);

        vm.prank(alice);
        token.transferFrom(alice, bob, TOKEN_1);

        assertEq(token.ownerOf(TOKEN_1), bob);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_TransferFromEmitsTransfer() public {
        helper.mint(alice, TOKEN_1);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, TOKEN_1);

        vm.prank(alice);
        token.transferFrom(alice, bob, TOKEN_1);
    }

    function test_TransferFromClearsApproval() public {
        helper.mint(alice, TOKEN_1);

        vm.prank(alice);
        token.approve(charlie, TOKEN_1);
        assertEq(token.getApproved(TOKEN_1), charlie);

        vm.prank(alice);
        token.transferFrom(alice, bob, TOKEN_1);

        assertEq(token.getApproved(TOKEN_1), address(0));
    }

    function test_TransferFromByNonOwnerNonOperatorReverts() public {
        helper.mint(alice, TOKEN_1);

        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InsufficientApproval.selector, charlie, TOKEN_1));
        vm.prank(charlie);
        token.transferFrom(alice, charlie, TOKEN_1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              APPROVAL TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ApproveSetsTokenApproval() public {
        helper.mint(alice, TOKEN_1);

        vm.prank(alice);
        token.approve(bob, TOKEN_1);

        assertEq(token.getApproved(TOKEN_1), bob);
    }

    function test_ApproveByNonOwnerNonOperatorReverts() public {
        helper.mint(alice, TOKEN_1);

        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidApprover.selector, charlie));
        vm.prank(charlie);
        token.approve(bob, TOKEN_1);
    }

    function test_ApprovedOperatorCanTransfer() public {
        helper.mint(alice, TOKEN_1);

        vm.prank(alice);
        token.approve(bob, TOKEN_1);

        vm.prank(bob);
        token.transferFrom(alice, charlie, TOKEN_1);

        assertEq(token.ownerOf(TOKEN_1), charlie);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         OPERATOR APPROVAL TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetApprovalForAll() public {
        vm.prank(alice);
        token.setApprovalForAll(bob, true);

        assertTrue(token.isApprovedForAll(alice, bob));
    }

    function test_RevokeApprovalForAll() public {
        vm.prank(alice);
        token.setApprovalForAll(bob, true);

        vm.prank(alice);
        token.setApprovalForAll(bob, false);

        assertFalse(token.isApprovedForAll(alice, bob));
    }

    function test_OperatorCanTransferAnyToken() public {
        helper.mint(alice, TOKEN_1);
        helper.mint(alice, TOKEN_2);

        vm.prank(alice);
        token.setApprovalForAll(bob, true);

        vm.prank(bob);
        token.transferFrom(alice, charlie, TOKEN_1);
        vm.prank(bob);
        token.transferFrom(alice, charlie, TOKEN_2);

        assertEq(token.ownerOf(TOKEN_1), charlie);
        assertEq(token.ownerOf(TOKEN_2), charlie);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         SAFE TRANSFER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SafeTransferFromToEOASucceeds() public {
        helper.mint(alice, TOKEN_1);

        vm.prank(alice);
        token.safeTransferFrom(alice, bob, TOKEN_1);

        assertEq(token.ownerOf(TOKEN_1), bob);
    }

    function test_SafeTransferFromToGoodReceiverSucceeds() public {
        GoodReceiver receiver = new GoodReceiver();

        helper.mint(alice, TOKEN_1);

        vm.prank(alice);
        token.safeTransferFrom(alice, address(receiver), TOKEN_1);

        assertEq(token.ownerOf(TOKEN_1), address(receiver));
    }

    function test_SafeTransferFromToBadReceiverReverts() public {
        BadReceiver receiver = new BadReceiver();

        helper.mint(alice, TOKEN_1);

        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidReceiver.selector, address(receiver)));
        vm.prank(alice);
        token.safeTransferFrom(alice, address(receiver), TOKEN_1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsERC721Interface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(0x80ac58cd)); // IERC721
    }

    function test_SupportsERC721MetadataInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(0x5b5e139f)); // IERC721Metadata
    }

    //*//////////////////////////////////////////////////////////////////////////
    //            IMP-01: Receiver revert reason bubbles up (ERC721 IMP-01)
    //////////////////////////////////////////////////////////////////////////*//

    function test_SafeMintToRevertingReceiver_BubblesCustomError() public {
        RevertingReceiver receiver = new RevertingReceiver();

        vm.expectRevert(RevertingReceiver.MintNotOpen.selector);
        helper.safeMint(address(receiver), TOKEN_1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //            IMP-02: _approve nonexistent token reverts (ERC721 IMP-02)
    //////////////////////////////////////////////////////////////////////////*//

    function test_ApproveNonexistentTokenReverts() public {
        // approve() calls _approve(..., auth=sender, emitEvent=true)
        // With auth != address(0), _requireOwned will revert for nonexistent token
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, TOKEN_1));
        vm.prank(alice);
        token.approve(bob, TOKEN_1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //            MIN-02: _increaseBalance helper
    //////////////////////////////////////////////////////////////////////////*//

    function test_IncreaseBalance_IncreasesCount() public {
        // Use transfer which internally calls _update → _increaseBalance path for to
        helper.mint(alice, TOKEN_1);

        // Initial balance is 1
        assertEq(token.balanceOf(alice), 1);

        // Transfer to bob increases bob's balance
        vm.prank(alice);
        token.transferFrom(alice, bob, TOKEN_1);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(alice), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //            MIN-03: _transfer and _safeTransfer internal helpers
    //////////////////////////////////////////////////////////////////////////*//

    function test_TransferHelper_MovesToken() public {
        helper.mint(alice, TOKEN_1);

        // helper.transfer bypasses auth (no prank needed)
        helper.transfer(alice, bob, TOKEN_1);
        assertEq(token.ownerOf(TOKEN_1), bob);
    }

    function test_TransferHelper_WrongFromReverts() public {
        helper.mint(alice, TOKEN_1);

        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721IncorrectOwner.selector, bob, TOKEN_1, alice));
        helper.transfer(bob, charlie, TOKEN_1);
    }

    function test_SafeTransferHelper_ToGoodReceiver() public {
        GoodReceiver receiver = new GoodReceiver();

        helper.mint(alice, TOKEN_1);

        helper.safeTransfer(alice, address(receiver), TOKEN_1);
        assertEq(token.ownerOf(TOKEN_1), address(receiver));
    }

    function test_SafeTransferHelper_ToRevertingReceiver_Bubbles() public {
        RevertingReceiver receiver = new RevertingReceiver();

        helper.mint(alice, TOKEN_1);

        vm.expectRevert(RevertingReceiver.MintNotOpen.selector);
        helper.safeTransfer(alice, address(receiver), TOKEN_1);
    }
}
