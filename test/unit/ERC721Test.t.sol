// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IERC721, IERC721Receiver} from "@lattice/interfaces/tokens/IERC721.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721Lib} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";
import {Test} from "forge-std/Test.sol";

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

/// @title MockERC721Contract
/// @notice Mock ERC-721 token for testing.
contract MockERC721Contract is ERC721, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function initialize(string memory name_, string memory symbol_, address admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC721Lib.__ERC721_init(name_, symbol_);
        AccessControlLib.__AccessControl_init(admin);
        InitializableLib.postInitializer(s);
    }

    /// @notice Admin-gated mint helper.
    function mintHelper(address to, uint256 tokenId) external {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC721Lib._mint(to, tokenId);
    }

    /// @notice Safe mint helper for testing receiver hooks.
    function safeMintHelper(address to, uint256 tokenId) external {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC721Lib._safeMint(to, tokenId);
    }

    /// @notice Exposes internal _transfer for testing.
    function transferHelper(address from, address to, uint256 tokenId) external {
        ERC721Lib._transfer(from, to, tokenId);
    }

    /// @notice Exposes internal _safeTransfer for testing.
    function safeTransferHelper(address from, address to, uint256 tokenId) external {
        ERC721Lib._safeTransfer(from, to, tokenId, "");
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC721Test
contract ERC721Test is Test {
    MockERC721Contract token;

    address admin = address(0xA);
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    uint256 constant TOKEN_1 = 1;
    uint256 constant TOKEN_2 = 2;
    uint256 constant TOKEN_3 = 3;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function setUp() public {
        token = new MockERC721Contract();
        token.initialize("Test NFT", "TNFT", admin);
    }

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
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        assertEq(token.balanceOf(alice), 1);
        assertEq(token.ownerOf(TOKEN_1), alice);
    }

    function test_MintEmitsTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, TOKEN_1);

        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);
    }

    function test_MintToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidReceiver.selector, address(0)));
        vm.prank(admin);
        token.mintHelper(address(0), TOKEN_1);
    }

    function test_MintExistingTokenReverts() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        // Minting same tokenId again: _update returns alice (non-zero), _mint reverts with ERC721InvalidSender
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidSender.selector, alice));
        vm.prank(admin);
        token.mintHelper(bob, TOKEN_1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               BALANCE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_BalanceOfReturnsCount() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_2);
        vm.prank(admin);
        token.mintHelper(bob, TOKEN_3);

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
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.prank(alice);
        token.transferFrom(alice, bob, TOKEN_1);

        assertEq(token.ownerOf(TOKEN_1), bob);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_TransferFromEmitsTransfer() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, TOKEN_1);

        vm.prank(alice);
        token.transferFrom(alice, bob, TOKEN_1);
    }

    function test_TransferFromClearsApproval() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.prank(alice);
        token.approve(charlie, TOKEN_1);
        assertEq(token.getApproved(TOKEN_1), charlie);

        vm.prank(alice);
        token.transferFrom(alice, bob, TOKEN_1);

        assertEq(token.getApproved(TOKEN_1), address(0));
    }

    function test_TransferFromByNonOwnerNonOperatorReverts() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InsufficientApproval.selector, charlie, TOKEN_1));
        vm.prank(charlie);
        token.transferFrom(alice, charlie, TOKEN_1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              APPROVAL TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ApproveSetsTokenApproval() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.prank(alice);
        token.approve(bob, TOKEN_1);

        assertEq(token.getApproved(TOKEN_1), bob);
    }

    function test_ApproveByNonOwnerNonOperatorReverts() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidApprover.selector, charlie));
        vm.prank(charlie);
        token.approve(bob, TOKEN_1);
    }

    function test_ApprovedOperatorCanTransfer() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

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
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_2);

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
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.prank(alice);
        token.safeTransferFrom(alice, bob, TOKEN_1);

        assertEq(token.ownerOf(TOKEN_1), bob);
    }

    function test_SafeTransferFromToGoodReceiverSucceeds() public {
        GoodReceiver receiver = new GoodReceiver();

        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.prank(alice);
        token.safeTransferFrom(alice, address(receiver), TOKEN_1);

        assertEq(token.ownerOf(TOKEN_1), address(receiver));
    }

    function test_SafeTransferFromToBadReceiverReverts() public {
        BadReceiver receiver = new BadReceiver();

        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidReceiver.selector, address(receiver)));
        vm.prank(alice);
        token.safeTransferFrom(alice, address(receiver), TOKEN_1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsERC721Interface() public view {
        assertTrue(token.supportsInterface(0x80ac58cd)); // IERC721
    }

    function test_SupportsERC721MetadataInterface() public view {
        assertTrue(token.supportsInterface(0x5b5e139f)); // IERC721Metadata
    }

    //*//////////////////////////////////////////////////////////////////////////
    //            IMP-01: Receiver revert reason bubbles up (ERC721 IMP-01)
    //////////////////////////////////////////////////////////////////////////*//

    function test_SafeMintToRevertingReceiver_BubblesCustomError() public {
        RevertingReceiver receiver = new RevertingReceiver();

        vm.expectRevert(RevertingReceiver.MintNotOpen.selector);
        vm.prank(admin);
        token.safeMintHelper(address(receiver), TOKEN_1);
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
        // Use transferHelper which internally calls _update → _increaseBalance path for to
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

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
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        // transferHelper bypasses auth (no prank needed)
        token.transferHelper(alice, bob, TOKEN_1);
        assertEq(token.ownerOf(TOKEN_1), bob);
    }

    function test_TransferHelper_WrongFromReverts() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721IncorrectOwner.selector, bob, TOKEN_1, alice));
        token.transferHelper(bob, charlie, TOKEN_1);
    }

    function test_SafeTransferHelper_ToGoodReceiver() public {
        GoodReceiver receiver = new GoodReceiver();

        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        token.safeTransferHelper(alice, address(receiver), TOKEN_1);
        assertEq(token.ownerOf(TOKEN_1), address(receiver));
    }

    function test_SafeTransferHelper_ToRevertingReceiver_Bubbles() public {
        RevertingReceiver receiver = new RevertingReceiver();

        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.expectRevert(RevertingReceiver.MintNotOpen.selector);
        token.safeTransferHelper(alice, address(receiver), TOKEN_1);
    }
}
