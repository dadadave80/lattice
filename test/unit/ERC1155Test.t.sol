// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ERC1155TestBase} from "@lattice-test/base/ERC1155TestBase.sol";
import {IERC1155} from "@lattice/interfaces/tokens/IERC1155.sol";

/// @notice ERC1155 receiver that returns correct selectors.
contract Good1155Receiver {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }
}

/// @notice ERC1155 receiver that returns wrong selectors.
contract Bad1155Receiver {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return bytes4(0);
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return bytes4(0);
    }
}

/// @notice ERC1155 receiver that deliberately reverts with a custom error on single transfer.
contract Reverting1155Receiver {
    error TransferBlocked();

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        revert TransferBlocked();
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert TransferBlocked();
    }
}

/// @title ERC1155Test
/// @notice Exercises the base ERC-1155 facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployERC1155} script (see {ERC1155TestBase}) — every call below routes through the diamond's
///         `delegatecall` dispatch, not a flattened inheritance mock. `mint`/`mintBatch`/`burn` come from the
///         test-only {ERC1155TestFacet} (`helper`); `supportsInterface` from the cut-in `ERC165Facet`. Mint
///         calls are pranked from `admin` to preserve the `operator == admin` event assertions.
contract ERC1155Test is ERC1155TestBase {
    address admin = address(0xA);
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    uint256 constant ID_1 = 1;
    uint256 constant ID_2 = 2;
    uint256 constant ID_3 = 3;

    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event TransferBatch(
        address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values
    );
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    //*//////////////////////////////////////////////////////////////////////////
    //                              URI TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_URIReturnsTemplate() public view {
        assertEq(token.uri(ID_1), "https://example.com/{id}");
        assertEq(token.uri(ID_2), "https://example.com/{id}");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               MINT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintUpdatesBalance() public {
        vm.prank(admin);
        helper.mint(alice, ID_1, 100, "");

        assertEq(token.balanceOf(alice, ID_1), 100);
    }

    function test_MintEmitsTransferSingle() public {
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(admin, address(0), alice, ID_1, 100);

        vm.prank(admin);
        helper.mint(alice, ID_1, 100, "");
    }

    function test_MintBatchUpdatesBalances() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = ID_1;
        ids[1] = ID_2;
        uint256[] memory values = new uint256[](2);
        values[0] = 100;
        values[1] = 200;

        vm.prank(admin);
        helper.mintBatch(alice, ids, values, "");

        assertEq(token.balanceOf(alice, ID_1), 100);
        assertEq(token.balanceOf(alice, ID_2), 200);
    }

    function test_MintBatchEmitsTransferBatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = ID_1;
        ids[1] = ID_2;
        uint256[] memory values = new uint256[](2);
        values[0] = 100;
        values[1] = 200;

        vm.expectEmit(true, true, true, false);
        emit TransferBatch(admin, address(0), alice, ids, values);

        vm.prank(admin);
        helper.mintBatch(alice, ids, values, "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            BALANCE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_BalanceOfBatchReturnsCorrectValues() public {
        vm.prank(admin);
        helper.mint(alice, ID_1, 10, "");
        vm.prank(admin);
        helper.mint(alice, ID_2, 20, "");
        vm.prank(admin);
        helper.mint(bob, ID_1, 5, "");

        address[] memory accounts = new address[](3);
        accounts[0] = alice;
        accounts[1] = alice;
        accounts[2] = bob;

        uint256[] memory ids = new uint256[](3);
        ids[0] = ID_1;
        ids[1] = ID_2;
        ids[2] = ID_1;

        uint256[] memory balances = token.balanceOfBatch(accounts, ids);
        assertEq(balances[0], 10);
        assertEq(balances[1], 20);
        assertEq(balances[2], 5);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         SAFE TRANSFER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SafeTransferFromByOwner() public {
        vm.prank(admin);
        helper.mint(alice, ID_1, 100, "");

        vm.prank(alice);
        token.safeTransferFrom(alice, bob, ID_1, 60, "");

        assertEq(token.balanceOf(alice, ID_1), 40);
        assertEq(token.balanceOf(bob, ID_1), 60);
    }

    function test_SafeTransferFromByApprovedOperator() public {
        vm.prank(admin);
        helper.mint(alice, ID_1, 100, "");

        vm.prank(alice);
        token.setApprovalForAll(bob, true);

        vm.prank(bob);
        token.safeTransferFrom(alice, charlie, ID_1, 50, "");

        assertEq(token.balanceOf(alice, ID_1), 50);
        assertEq(token.balanceOf(charlie, ID_1), 50);
    }

    function test_SafeTransferFromWithoutApprovalReverts() public {
        vm.prank(admin);
        helper.mint(alice, ID_1, 100, "");

        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155MissingApprovalForAll.selector, charlie, alice));
        vm.prank(charlie);
        token.safeTransferFrom(alice, charlie, ID_1, 50, "");
    }

    function test_SafeTransferFromInsufficientBalanceReverts() public {
        vm.prank(admin);
        helper.mint(alice, ID_1, 10, "");

        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InsufficientBalance.selector, alice, 10, 100, ID_1));
        vm.prank(alice);
        token.safeTransferFrom(alice, bob, ID_1, 100, "");
    }

    function test_SafeBatchTransferFromMismatchedArrayLengthsReverts() public {
        vm.prank(admin);
        helper.mint(alice, ID_1, 100, "");

        uint256[] memory ids = new uint256[](2);
        ids[0] = ID_1;
        ids[1] = ID_2;
        uint256[] memory values = new uint256[](1);
        values[0] = 50;

        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidArrayLength.selector, uint256(2), uint256(1)));
        vm.prank(alice);
        token.safeBatchTransferFrom(alice, bob, ids, values, "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       SAFE RECEIVER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SafeTransferFromToGoodReceiverSucceeds() public {
        Good1155Receiver receiver = new Good1155Receiver();

        vm.prank(admin);
        helper.mint(alice, ID_1, 100, "");

        vm.prank(alice);
        token.safeTransferFrom(alice, address(receiver), ID_1, 50, "");

        assertEq(token.balanceOf(address(receiver), ID_1), 50);
    }

    function test_SafeTransferFromToBadReceiverReverts() public {
        Bad1155Receiver receiver = new Bad1155Receiver();

        vm.prank(admin);
        helper.mint(alice, ID_1, 100, "");

        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidReceiver.selector, address(receiver)));
        vm.prank(alice);
        token.safeTransferFrom(alice, address(receiver), ID_1, 50, "");
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

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsERC1155Interface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(0xd9b67a26)); // IERC1155
    }

    function test_SupportsERC1155MetadataURIInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(0x0e89341c)); // IERC1155MetadataURI
    }

    //*//////////////////////////////////////////////////////////////////////////
    //       IMP-01: Receiver revert reason bubbles up (ERC1155 IMP-01)
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintToRevertingReceiver_BubblesCustomError() public {
        Reverting1155Receiver receiver = new Reverting1155Receiver();

        vm.expectRevert(Reverting1155Receiver.TransferBlocked.selector);
        vm.prank(admin);
        helper.mint(address(receiver), ID_1, 100, "");
    }

    function test_MintBatchToRevertingReceiver_BubblesCustomError() public {
        Reverting1155Receiver receiver = new Reverting1155Receiver();

        uint256[] memory ids = new uint256[](2);
        ids[0] = ID_1;
        ids[1] = ID_2;
        uint256[] memory values = new uint256[](2);
        values[0] = 10;
        values[1] = 20;

        vm.expectRevert(Reverting1155Receiver.TransferBlocked.selector);
        vm.prank(admin);
        helper.mintBatch(address(receiver), ids, values, "");
    }

    function test_SafeTransferToRevertingReceiver_BubblesCustomError() public {
        Reverting1155Receiver receiver = new Reverting1155Receiver();

        vm.prank(admin);
        helper.mint(alice, ID_1, 100, "");

        vm.expectRevert(Reverting1155Receiver.TransferBlocked.selector);
        vm.prank(alice);
        token.safeTransferFrom(alice, address(receiver), ID_1, 50, "");
    }
}
