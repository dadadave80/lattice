// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC1155Supply} from "@lattice-script/base/tokens/DeployERC1155Supply.s.sol";
import {ERC1155TestBase} from "@lattice-test/base/ERC1155TestBase.sol";
import {ERC1155SupplyTestFacet} from "@lattice-test/helpers/ERC1155SupplyTestFacet.sol";
import {ERC1155TestFacet} from "@lattice-test/helpers/ERC1155TestFacet.sol";
import {Recording1155Receiver} from "@lattice-test/helpers/Recording1155Receiver.sol";
import {IERC1155} from "@lattice/interfaces/tokens/IERC1155.sol";
import {IERC1155Burnable} from "@lattice/interfaces/tokens/IERC1155Burnable.sol";
import {IERC1155Supply} from "@lattice/interfaces/tokens/IERC1155Supply.sol";
import {ERC1155} from "@lattice/tokens/ERC1155/ERC1155.sol";
import {stdError} from "forge-std/StdError.sol";

/// @notice Receiver that records the supply it reads from the token inside the acceptance callback, to pin that
///         the supply counters are written before the callback runs (as in OpenZeppelin's `_update` ordering).
contract SupplyProbe1155Receiver {
    uint256 public seenIdSupply;
    uint256 public seenTotalSupply;
    bool public seenExists;

    function onERC1155Received(address, address, uint256 id, uint256, bytes calldata) external returns (bytes4) {
        _record(id);
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata ids, uint256[] calldata, bytes calldata)
        external
        returns (bytes4)
    {
        _record(ids[0]);
        return this.onERC1155BatchReceived.selector;
    }

    function _record(uint256 id) private {
        IERC1155Supply token = IERC1155Supply(msg.sender);
        seenIdSupply = token.totalSupply(id);
        seenTotalSupply = token.totalSupply();
        seenExists = token.exists(id);
    }
}

/// @title ERC1155SupplyTest
/// @notice Exercises the {ERC1155Supply} facet through a REAL diamond assembled by the {DeployERC1155Supply} recipe
///         (base ERC-1155 + the supply facet, whose `burn`/`burnBatch` track supply). Seeding mints go through the
///         test-only {ERC1155SupplyTestFacet}, which mints via {ERC1155SupplyLib} as a production mint facet must.
contract ERC1155SupplyTest is ERC1155TestBase {
    IERC1155Supply internal supply;
    IERC1155Burnable internal burnable;

    address alice = address(0x1);
    address bob = address(0x2);
    address carol = address(0x3);

    uint256 constant ID_1 = 1;
    uint256 constant ID_2 = 2;
    uint256 constant ID_3 = 3;

    function setUp() public override {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            new DeployERC1155Supply().buildCuts("https://example.com/{id}");
        diamond = _deployWithHelper(cuts, inits, initCalldatas, address(new ERC1155SupplyTestFacet()));
        token = ERC1155(diamond);
        helper = ERC1155TestFacet(diamond);
        supply = IERC1155Supply(diamond);
        burnable = IERC1155Burnable(diamond);
    }

    function _pair(uint256 a, uint256 b) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    function test_FreshTokenHasNoSupply() public view {
        assertEq(supply.totalSupply(ID_1), 0);
        assertEq(supply.totalSupply(), 0);
        assertFalse(supply.exists(ID_1));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   MINT
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintIncreasesSupply() public {
        helper.mint(alice, ID_1, 100, "");
        helper.mint(bob, ID_1, 20, "");
        helper.mint(alice, ID_2, 5, "");

        assertEq(supply.totalSupply(ID_1), 120);
        assertEq(supply.totalSupply(ID_2), 5);
        assertEq(supply.totalSupply(), 125);
        assertTrue(supply.exists(ID_1));
        assertTrue(supply.exists(ID_2));
        assertFalse(supply.exists(ID_3));
    }

    function test_MintBatchIncreasesSupply() public {
        helper.mintBatch(alice, _pair(ID_1, ID_2), _pair(7, 9), "");

        assertEq(supply.totalSupply(ID_1), 7);
        assertEq(supply.totalSupply(ID_2), 9);
        assertEq(supply.totalSupply(), 16);
    }

    function test_MintBatchWithRepeatedIdCountsBoth() public {
        helper.mintBatch(alice, _pair(ID_1, ID_1), _pair(7, 9), "");

        assertEq(supply.totalSupply(ID_1), 16);
        assertEq(supply.totalSupply(), 16);
        assertEq(token.balanceOf(alice, ID_1), 16);
    }

    function test_MintZeroValueDoesNotCreateId() public {
        helper.mint(alice, ID_1, 0, "");
        assertFalse(supply.exists(ID_1));
    }

    /// @notice The supply counters are written before the receiver callback, so a receiver reading the token
    ///         from inside `onERC1155Received` sees the post-mint supply, as in OpenZeppelin.
    function test_ReceiverSeesUpdatedSupplyDuringMint() public {
        SupplyProbe1155Receiver probe = new SupplyProbe1155Receiver();
        helper.mint(alice, ID_1, 10, "");
        helper.mint(address(probe), ID_1, 5, "");

        assertEq(probe.seenIdSupply(), 15);
        assertEq(probe.seenTotalSupply(), 15);
        assertTrue(probe.seenExists());
    }

    function test_ReceiverSeesUpdatedSupplyDuringMintBatch() public {
        SupplyProbe1155Receiver probe = new SupplyProbe1155Receiver();
        helper.mintBatch(address(probe), _pair(ID_2, ID_3), _pair(4, 6), "");

        assertEq(probe.seenIdSupply(), 4);
        assertEq(probe.seenTotalSupply(), 10);
    }

    function test_MintToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidReceiver.selector, address(0)));
        helper.mint(address(0), ID_1, 1, "");
    }

    function test_MintBatchToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidReceiver.selector, address(0)));
        helper.mintBatch(address(0), _pair(ID_1, ID_2), _pair(1, 1), "");
    }

    /// @notice {ERC1155SupplyLib} runs its own receiver check, so it is pinned here too (#237): a one-element
    ///         mint batch calls `onERC1155BatchReceived`, and `data` reaches the receiver on both paths.
    function test_OneElementMintBatchCallsBatchHookWithData() public {
        Recording1155Receiver receiver = new Recording1155Receiver();
        uint256[] memory ids = new uint256[](1);
        ids[0] = ID_2;
        uint256[] memory values = new uint256[](1);
        values[0] = 7;
        helper.mintBatch(address(receiver), ids, values, "mint-batch-data");

        assertEq(uint8(receiver.lastHook()), uint8(Recording1155Receiver.Hook.Batch), "batch hook expected");
        assertEq(receiver.batchIdsLength(), 1);
        assertEq(receiver.lastData(), "mint-batch-data");
        assertEq(receiver.lastOperator(), address(this));
        assertEq(supply.totalSupply(ID_2), 7);
    }

    function test_MintCallsSingleHookWithData() public {
        Recording1155Receiver receiver = new Recording1155Receiver();
        helper.mint(address(receiver), ID_1, 5, "mint-data");

        assertEq(uint8(receiver.lastHook()), uint8(Recording1155Receiver.Hook.Single), "single hook expected");
        assertEq(receiver.lastData(), "mint-data");
        assertEq(receiver.lastOperator(), address(this));
        assertEq(supply.totalSupply(ID_1), 5);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             OVERFLOW (OZ v5.6.1)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Per-id supply is checked: a second holder's mint overflows `totalSupply(id)` even though neither
    ///         balance overflows.
    function test_IdSupplyOverflowReverts() public {
        helper.mint(alice, ID_1, type(uint256).max, "");
        vm.expectRevert(stdError.arithmeticError);
        helper.mint(bob, ID_1, 1, "");
    }

    /// @notice The all-ids total is checked too: it caps the sum over every id at `type(uint256).max`, so a mint
    ///         of a fresh id reverts once the global total is full.
    function test_TotalSupplyAllOverflowReverts() public {
        helper.mint(alice, ID_1, type(uint256).max, "");
        vm.expectRevert(stdError.arithmeticError);
        helper.mint(bob, ID_2, 1, "");
    }

    /// @notice A batch whose values sum past `type(uint256).max` reverts while summing, before the total moves.
    function test_BatchMintValueSumOverflowReverts() public {
        vm.expectRevert(stdError.arithmeticError);
        helper.mintBatch(alice, _pair(ID_1, ID_2), _pair(type(uint256).max, 1), "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   BURN
    //////////////////////////////////////////////////////////////////////////*//

    function test_BurnDecreasesSupply() public {
        helper.mint(alice, ID_1, 100, "");
        helper.mint(alice, ID_2, 50, "");

        vm.prank(alice);
        burnable.burn(alice, ID_1, 30);

        assertEq(token.balanceOf(alice, ID_1), 70);
        assertEq(supply.totalSupply(ID_1), 70);
        assertEq(supply.totalSupply(), 120);
    }

    function test_BurnToZeroClearsExists() public {
        helper.mint(alice, ID_1, 10, "");
        vm.prank(alice);
        burnable.burn(alice, ID_1, 10);
        assertFalse(supply.exists(ID_1));
        assertEq(supply.totalSupply(), 0);
    }

    function test_BurnBatchDecreasesSupply() public {
        helper.mintBatch(alice, _pair(ID_1, ID_2), _pair(10, 20), "");
        vm.prank(alice);
        burnable.burnBatch(alice, _pair(ID_1, ID_2), _pair(4, 20));

        assertEq(supply.totalSupply(ID_1), 6);
        assertEq(supply.totalSupply(ID_2), 0);
        assertFalse(supply.exists(ID_2));
        assertEq(supply.totalSupply(), 6);
    }

    function test_BurnByApprovedOperatorDecreasesSupply() public {
        helper.mint(alice, ID_1, 10, "");
        vm.prank(alice);
        token.setApprovalForAll(bob, true);

        vm.prank(bob);
        burnable.burn(alice, ID_1, 4);
        assertEq(supply.totalSupply(ID_1), 6);
    }

    function test_BurnUnapprovedReverts() public {
        helper.mint(alice, ID_1, 10, "");
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155MissingApprovalForAll.selector, bob, alice));
        vm.prank(bob);
        burnable.burn(alice, ID_1, 1);
    }

    function test_BurnBatchUnapprovedReverts() public {
        helper.mintBatch(alice, _pair(ID_1, ID_2), _pair(10, 10), "");
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155MissingApprovalForAll.selector, bob, alice));
        vm.prank(bob);
        burnable.burnBatch(alice, _pair(ID_1, ID_2), _pair(1, 1));
    }

    function test_BurnBatchFromZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidSender.selector, address(0)));
        vm.prank(address(0));
        burnable.burnBatch(address(0), _pair(ID_1, ID_2), _pair(0, 0));
    }

    function test_BurnFromZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidSender.selector, address(0)));
        vm.prank(address(0));
        burnable.burn(address(0), ID_1, 0);
    }

    function test_BurnInsufficientBalanceReverts() public {
        helper.mint(alice, ID_1, 10, "");
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InsufficientBalance.selector, alice, 10, 11, ID_1));
        vm.prank(alice);
        burnable.burn(alice, ID_1, 11);
    }

    function test_BurnBatchMismatchedArrayLengthsReverts() public {
        uint256[] memory values = new uint256[](1);
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidArrayLength.selector, 2, 1));
        vm.prank(alice);
        burnable.burnBatch(alice, _pair(ID_1, ID_2), values);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 TRANSFER
    //////////////////////////////////////////////////////////////////////////*//

    function test_TransfersLeaveSupplyUnchanged() public {
        helper.mintBatch(alice, _pair(ID_1, ID_2), _pair(10, 20), "");

        vm.startPrank(alice);
        token.safeTransferFrom(alice, bob, ID_1, 3, "");
        token.safeBatchTransferFrom(alice, carol, _pair(ID_1, ID_2), _pair(2, 5), "");
        vm.stopPrank();

        assertEq(supply.totalSupply(ID_1), 10);
        assertEq(supply.totalSupply(ID_2), 20);
        assertEq(supply.totalSupply(), 30);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   FUZZ
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Mint then burn keeps `totalSupply(id)` equal to the holders' balances and `totalSupply()` equal to
    ///         the sum over ids.
    function testFuzz_SupplyTracksMintAndBurn(uint128 a, uint128 b, uint128 burned) public {
        helper.mint(alice, ID_1, a, "");
        helper.mint(bob, ID_2, b, "");
        uint256 burn = bound(burned, 0, a);
        vm.prank(alice);
        burnable.burn(alice, ID_1, burn);

        assertEq(supply.totalSupply(ID_1), token.balanceOf(alice, ID_1));
        assertEq(supply.totalSupply(ID_2), token.balanceOf(bob, ID_2));
        assertEq(supply.totalSupply(), supply.totalSupply(ID_1) + supply.totalSupply(ID_2));
        assertEq(supply.exists(ID_1), uint256(a) - burn > 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsInterface() public view {
        assertEq(type(IERC1155Supply).interfaceId, bytes4(0xeac6339d));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC1155Supply).interfaceId));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC1155Burnable).interfaceId));
        assertTrue(ERC165Facet(diamond).supportsInterface(0xd9b67a26)); // IERC1155 (base)
    }
}
