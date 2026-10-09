// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC1155Burnable} from "@lattice-script/base/tokens/DeployERC1155Burnable.s.sol";
import {ERC1155TestBase} from "@lattice-test/base/ERC1155TestBase.sol";
import {ERC1155TestFacet} from "@lattice-test/helpers/ERC1155TestFacet.sol";
import {IERC1155} from "@lattice/interfaces/tokens/IERC1155.sol";
import {IERC1155Burnable} from "@lattice/interfaces/tokens/IERC1155Burnable.sol";
import {ERC1155} from "@lattice/tokens/ERC1155/ERC1155.sol";

/// @title ERC1155BurnableTest
/// @notice Exercises the {ERC1155Burnable} facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployERC1155Burnable} script (base ERC-1155 + the additive burnable facet). Every call routes through
///         the diamond's `delegatecall` dispatch; `mint`/`mintBatch` come from the test-only {ERC1155TestFacet}
///         (`helper`) and `supportsInterface` from the cut-in `ERC165Facet`.
contract ERC1155BurnableTest is ERC1155TestBase {
    IERC1155Burnable internal burnable;

    address alice = address(0x1);
    address bob = address(0x2);
    address carol = address(0x3);

    uint256 constant ID_1 = 1;
    uint256 constant ID_2 = 2;

    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event TransferBatch(
        address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values
    );

    function setUp() public override {
        DeployERC1155Burnable d = new DeployERC1155Burnable();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            d.buildCuts("https://example.com/{id}");
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC1155(diamond);
        helper = ERC1155TestFacet(diamond);
        burnable = IERC1155Burnable(diamond);

        helper.mint(alice, ID_1, 100, "");
        helper.mint(alice, ID_2, 50, "");
    }

    function _pair(uint256 a, uint256 b) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   BURN
    //////////////////////////////////////////////////////////////////////////*//

    function test_BurnByOwner() public {
        vm.prank(alice);
        burnable.burn(alice, ID_1, 30);
        assertEq(token.balanceOf(alice, ID_1), 70);
    }

    function test_BurnByApprovedOperator() public {
        vm.prank(alice);
        token.setApprovalForAll(bob, true);

        vm.prank(bob);
        burnable.burn(alice, ID_1, 100);
        assertEq(token.balanceOf(alice, ID_1), 0);
    }

    function test_BurnEmitsTransferSingleToZero() public {
        vm.expectEmit(true, true, true, true, diamond);
        emit TransferSingle(alice, alice, address(0), ID_1, 30);
        vm.prank(alice);
        burnable.burn(alice, ID_1, 30);
    }

    function test_BurnByOperatorEmitsOperator() public {
        vm.prank(alice);
        token.setApprovalForAll(bob, true);

        vm.expectEmit(true, true, true, true, diamond);
        emit TransferSingle(bob, alice, address(0), ID_1, 10);
        vm.prank(bob);
        burnable.burn(alice, ID_1, 10);
    }

    function test_BurnUnapprovedReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155MissingApprovalForAll.selector, bob, alice));
        vm.prank(bob);
        burnable.burn(alice, ID_1, 1);
    }

    function test_BurnAfterApprovalRevokedReverts() public {
        vm.prank(alice);
        token.setApprovalForAll(bob, true);
        vm.prank(alice);
        token.setApprovalForAll(bob, false);

        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155MissingApprovalForAll.selector, bob, alice));
        vm.prank(bob);
        burnable.burn(alice, ID_1, 1);
    }

    /// @notice A burn from address 0 reverts `ERC1155InvalidSender(0)`. The authorization check runs first, so
    ///         only a call from address 0 itself reaches the sender check (as in OpenZeppelin).
    function test_BurnFromZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidSender.selector, address(0)));
        vm.prank(address(0));
        burnable.burn(address(0), ID_1, 0);
    }

    function test_BurnInsufficientBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InsufficientBalance.selector, alice, 100, 101, ID_1));
        vm.prank(alice);
        burnable.burn(alice, ID_1, 101);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                BURN BATCH
    //////////////////////////////////////////////////////////////////////////*//

    function test_BurnBatchByOwner() public {
        vm.prank(alice);
        burnable.burnBatch(alice, _pair(ID_1, ID_2), _pair(40, 50));
        assertEq(token.balanceOf(alice, ID_1), 60);
        assertEq(token.balanceOf(alice, ID_2), 0);
    }

    function test_BurnBatchByApprovedOperator() public {
        vm.prank(alice);
        token.setApprovalForAll(bob, true);

        vm.prank(bob);
        burnable.burnBatch(alice, _pair(ID_1, ID_2), _pair(1, 2));
        assertEq(token.balanceOf(alice, ID_1), 99);
        assertEq(token.balanceOf(alice, ID_2), 48);
    }

    function test_BurnBatchEmitsTransferBatchToZero() public {
        vm.expectEmit(true, true, true, true, diamond);
        emit TransferBatch(alice, alice, address(0), _pair(ID_1, ID_2), _pair(5, 6));
        vm.prank(alice);
        burnable.burnBatch(alice, _pair(ID_1, ID_2), _pair(5, 6));
    }

    function test_BurnBatchUnapprovedReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155MissingApprovalForAll.selector, carol, alice));
        vm.prank(carol);
        burnable.burnBatch(alice, _pair(ID_1, ID_2), _pair(1, 1));
    }

    function test_BurnBatchFromZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidSender.selector, address(0)));
        vm.prank(address(0));
        burnable.burnBatch(address(0), _pair(ID_1, ID_2), _pair(0, 0));
    }

    function test_BurnBatchMismatchedArrayLengthsReverts() public {
        uint256[] memory values = new uint256[](1);
        values[0] = 1;
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidArrayLength.selector, 2, 1));
        vm.prank(alice);
        burnable.burnBatch(alice, _pair(ID_1, ID_2), values);
    }

    function test_BurnBatchInsufficientBalanceRevertsAtomically() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InsufficientBalance.selector, alice, 50, 51, ID_2));
        vm.prank(alice);
        burnable.burnBatch(alice, _pair(ID_1, ID_2), _pair(10, 51));
        assertEq(token.balanceOf(alice, ID_1), 100);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   FUZZ
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Burning any amount up to the balance debits exactly that amount and leaves other ids untouched.
    function testFuzz_BurnDebitsExactly(uint256 minted, uint256 burned) public {
        burned = bound(burned, 0, minted);
        helper.mint(carol, ID_1, minted, "");

        vm.prank(carol);
        burnable.burn(carol, ID_1, burned);

        assertEq(token.balanceOf(carol, ID_1), minted - burned);
        assertEq(token.balanceOf(alice, ID_1), 100);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsInterface() public view {
        assertEq(type(IERC1155Burnable).interfaceId, bytes4(0x9e094e9e));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC1155Burnable).interfaceId));
        assertTrue(ERC165Facet(diamond).supportsInterface(0xd9b67a26)); // IERC1155 (base)
    }
}
