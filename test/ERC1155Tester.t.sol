// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC1155} from "@lattice/tokens/ERC1155.sol";
import {ERC1155Lib} from "@lattice/tokens/libraries/ERC1155Lib.sol";
import {IERC1155, IERC1155Receiver} from "@lattice/interfaces/IERC1155.sol";
import {Test} from "forge-std/Test.sol";

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

/// @title MockERC1155Contract
/// @notice Mock ERC-1155 multi-token for testing.
contract MockERC1155Contract is ERC1155, AccessControl {
    function initialize(string memory uri_, address admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC1155Lib.__ERC1155_init(uri_);
        AccessControlLib.__AccessControl_init(admin);
        InitializableLib.postInitializer(s);
    }

    /// @notice Admin-gated single-mint helper.
    function mintHelper(address to, uint256 id, uint256 value, bytes calldata data) external {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC1155Lib._mint(to, id, value, data);
    }

    /// @notice Admin-gated batch-mint helper.
    function mintBatchHelper(address to, uint256[] calldata ids, uint256[] calldata values, bytes calldata data)
        external
    {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC1155Lib._mintBatch(to, ids, values, data);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC1155Tester
contract ERC1155Tester is Test {
    MockERC1155Contract token;

    address admin = address(0xA);
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    uint256 constant ID_1 = 1;
    uint256 constant ID_2 = 2;
    uint256 constant ID_3 = 3;

    event TransferSingle(
        address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value
    );
    event TransferBatch(
        address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values
    );
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    function setUp() public {
        token = new MockERC1155Contract();
        token.initialize("https://example.com/{id}", admin);
    }

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
        token.mintHelper(alice, ID_1, 100, "");

        assertEq(token.balanceOf(alice, ID_1), 100);
    }

    function test_MintEmitsTransferSingle() public {
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(admin, address(0), alice, ID_1, 100);

        vm.prank(admin);
        token.mintHelper(alice, ID_1, 100, "");
    }

    function test_MintBatchUpdatesBalances() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = ID_1;
        ids[1] = ID_2;
        uint256[] memory values = new uint256[](2);
        values[0] = 100;
        values[1] = 200;

        vm.prank(admin);
        token.mintBatchHelper(alice, ids, values, "");

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
        token.mintBatchHelper(alice, ids, values, "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            BALANCE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_BalanceOfBatchReturnsCorrectValues() public {
        vm.prank(admin);
        token.mintHelper(alice, ID_1, 10, "");
        vm.prank(admin);
        token.mintHelper(alice, ID_2, 20, "");
        vm.prank(admin);
        token.mintHelper(bob, ID_1, 5, "");

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
        token.mintHelper(alice, ID_1, 100, "");

        vm.prank(alice);
        token.safeTransferFrom(alice, bob, ID_1, 60, "");

        assertEq(token.balanceOf(alice, ID_1), 40);
        assertEq(token.balanceOf(bob, ID_1), 60);
    }

    function test_SafeTransferFromByApprovedOperator() public {
        vm.prank(admin);
        token.mintHelper(alice, ID_1, 100, "");

        vm.prank(alice);
        token.setApprovalForAll(bob, true);

        vm.prank(bob);
        token.safeTransferFrom(alice, charlie, ID_1, 50, "");

        assertEq(token.balanceOf(alice, ID_1), 50);
        assertEq(token.balanceOf(charlie, ID_1), 50);
    }

    function test_SafeTransferFromWithoutApprovalReverts() public {
        vm.prank(admin);
        token.mintHelper(alice, ID_1, 100, "");

        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155MissingApprovalForAll.selector, charlie, alice));
        vm.prank(charlie);
        token.safeTransferFrom(alice, charlie, ID_1, 50, "");
    }

    function test_SafeTransferFromInsufficientBalanceReverts() public {
        vm.prank(admin);
        token.mintHelper(alice, ID_1, 10, "");

        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InsufficientBalance.selector, alice, 10, 100, ID_1));
        vm.prank(alice);
        token.safeTransferFrom(alice, bob, ID_1, 100, "");
    }

    function test_SafeBatchTransferFromMismatchedArrayLengthsReverts() public {
        vm.prank(admin);
        token.mintHelper(alice, ID_1, 100, "");

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
        token.mintHelper(alice, ID_1, 100, "");

        vm.prank(alice);
        token.safeTransferFrom(alice, address(receiver), ID_1, 50, "");

        assertEq(token.balanceOf(address(receiver), ID_1), 50);
    }

    function test_SafeTransferFromToBadReceiverReverts() public {
        Bad1155Receiver receiver = new Bad1155Receiver();

        vm.prank(admin);
        token.mintHelper(alice, ID_1, 100, "");

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
        assertTrue(token.supportsInterface(0xd9b67a26)); // IERC1155
    }

    function test_SupportsERC1155MetadataURIInterface() public view {
        assertTrue(token.supportsInterface(0x0e89341c)); // IERC1155MetadataURI
    }

    //*//////////////////////////////////////////////////////////////////////////
    //       IMP-01: Receiver revert reason bubbles up (ERC1155 IMP-01)
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintToRevertingReceiver_BubblesCustomError() public {
        Reverting1155Receiver receiver = new Reverting1155Receiver();

        vm.expectRevert(Reverting1155Receiver.TransferBlocked.selector);
        vm.prank(admin);
        token.mintHelper(address(receiver), ID_1, 100, "");
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
        token.mintBatchHelper(address(receiver), ids, values, "");
    }

    function test_SafeTransferToRevertingReceiver_BubblesCustomError() public {
        Reverting1155Receiver receiver = new Reverting1155Receiver();

        vm.prank(admin);
        token.mintHelper(alice, ID_1, 100, "");

        vm.expectRevert(Reverting1155Receiver.TransferBlocked.selector);
        vm.prank(alice);
        token.safeTransferFrom(alice, address(receiver), ID_1, 50, "");
    }
}
