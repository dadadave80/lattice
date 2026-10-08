// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC1155Pausable} from "@lattice-script/base/tokens/DeployERC1155Pausable.s.sol";
import {ERC1155TestBase} from "@lattice-test/base/ERC1155TestBase.sol";
import {ERC1155PausableTestFacet} from "@lattice-test/helpers/ERC1155PausableTestFacet.sol";
import {ERC1155TestFacet} from "@lattice-test/helpers/ERC1155TestFacet.sol";
import {Recording1155Receiver} from "@lattice-test/helpers/Recording1155Receiver.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {IERC1155} from "@lattice/interfaces/tokens/IERC1155.sol";
import {IERC1155Burnable} from "@lattice/interfaces/tokens/IERC1155Burnable.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {ERC1155} from "@lattice/tokens/ERC1155/ERC1155.sol";

/// @title ERC1155PausableTest
/// @notice Exercises the {ERC1155Pausable} facet through a REAL diamond assembled by the {DeployERC1155Pausable}
///         recipe: base ERC-1155, the {Pausable} control facet, and {ERC1155Pausable}, which REPLACES the base
///         `safeTransferFrom`/`safeBatchTransferFrom` and serves pause-gated `burn`/`burnBatch`. Mints go through
///         the test-only {ERC1155PausableTestFacet}, which mints via {ERC1155PausableLib} as a production mint
///         facet must. The pause authority (DEFAULT_ADMIN_ROLE) is this test contract.
contract ERC1155PausableTest is ERC1155TestBase {
    Pausable internal pausable;
    IERC1155Burnable internal burnable;

    address admin = address(this);
    address alice = address(0x1);
    address bob = address(0x2);
    address carol = address(0x3);

    uint256 constant ID_1 = 1;
    uint256 constant ID_2 = 2;

    function setUp() public override {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            new DeployERC1155Pausable().buildCuts("https://example.com/{id}", admin);
        diamond = _deployWithHelper(cuts, inits, initCalldatas, address(new ERC1155PausableTestFacet()));
        token = ERC1155(diamond);
        helper = ERC1155TestFacet(diamond);
        pausable = Pausable(diamond);
        burnable = IERC1155Burnable(diamond);

        helper.mintBatch(alice, _pair(ID_1, ID_2), _pair(100, 50), "");
    }

    function _pair(uint256 a, uint256 b) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _one(uint256 a) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = a;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 UNPAUSED
    //////////////////////////////////////////////////////////////////////////*//

    function test_EverythingWorksWhenNotPaused() public {
        vm.startPrank(alice);
        token.safeTransferFrom(alice, bob, ID_1, 10, "");
        token.safeBatchTransferFrom(alice, bob, _pair(ID_1, ID_2), _pair(1, 2), "");
        burnable.burn(alice, ID_1, 5);
        burnable.burnBatch(alice, _pair(ID_1, ID_2), _pair(1, 1));
        vm.stopPrank();
        helper.mint(carol, ID_1, 7, "");

        assertEq(token.balanceOf(alice, ID_1), 83);
        assertEq(token.balanceOf(alice, ID_2), 47);
        assertEq(token.balanceOf(bob, ID_1), 11);
        assertEq(token.balanceOf(bob, ID_2), 2);
        assertEq(token.balanceOf(carol, ID_1), 7);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //       UNPAUSED CHECKS: the replaced selectors keep the base checks
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice {ERC1155Pausable} replaces the base transfer selectors, so its own copies of the authorization and
    ///         zero-address checks are what guard every transfer on a pausable diamond.
    function test_UnauthorizedSafeTransferRevertsMissingApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155MissingApprovalForAll.selector, bob, alice));
        vm.prank(bob);
        token.safeTransferFrom(alice, bob, ID_1, 1, "");
    }

    function test_UnauthorizedSafeBatchTransferRevertsMissingApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155MissingApprovalForAll.selector, bob, alice));
        vm.prank(bob);
        token.safeBatchTransferFrom(alice, bob, _pair(ID_1, ID_2), _pair(1, 1), "");
    }

    function test_UnauthorizedBurnRevertsMissingApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155MissingApprovalForAll.selector, bob, alice));
        vm.prank(bob);
        burnable.burn(alice, ID_1, 1);
    }

    function test_UnauthorizedBurnBatchRevertsMissingApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155MissingApprovalForAll.selector, bob, alice));
        vm.prank(bob);
        burnable.burnBatch(alice, _pair(ID_1, ID_2), _pair(1, 1));
    }

    function test_BurnByApprovedOperator() public {
        vm.prank(alice);
        token.setApprovalForAll(bob, true);
        vm.prank(bob);
        burnable.burn(alice, ID_1, 4);
        assertEq(token.balanceOf(alice, ID_1), 96);
    }

    /// @notice Without the receiver check `_update` would take its burn branch and silently destroy the tokens.
    function test_SafeTransferToZeroRevertsInvalidReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.safeTransferFrom(alice, address(0), ID_1, 1, "");
        assertEq(token.balanceOf(alice, ID_1), 100);
    }

    function test_SafeBatchTransferToZeroRevertsInvalidReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.safeBatchTransferFrom(alice, address(0), _pair(ID_1, ID_2), _pair(1, 1), "");
    }

    /// @notice Without the sender check `_update` would take its mint branch and credit `bob` from nothing.
    function test_SafeTransferFromZeroRevertsInvalidSender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.safeTransferFrom(address(0), bob, ID_1, 1, "");
    }

    function test_SafeBatchTransferFromZeroRevertsInvalidSender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.safeBatchTransferFrom(address(0), bob, _pair(ID_1, ID_2), _pair(1, 1), "");
    }

    function test_BurnFromZeroRevertsInvalidSender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidSender.selector, address(0)));
        vm.prank(address(0));
        burnable.burn(address(0), ID_1, 0);
    }

    function test_BurnBatchFromZeroRevertsInvalidSender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidSender.selector, address(0)));
        vm.prank(address(0));
        burnable.burnBatch(address(0), _pair(ID_1, ID_2), _pair(0, 0));
    }

    function test_MintToZeroRevertsInvalidReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidReceiver.selector, address(0)));
        helper.mint(address(0), ID_1, 1, "");
    }

    function test_MintBatchToZeroRevertsInvalidReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidReceiver.selector, address(0)));
        helper.mintBatch(address(0), _pair(ID_1, ID_2), _pair(1, 1), "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //     RECEIVER HOOK SELECTION AND DATA FORWARDING (#237, own paths)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A one-element `safeBatchTransferFrom` is a batch operation and calls `onERC1155BatchReceived`.
    function test_OneElementSafeBatchTransferCallsBatchHookWithData() public {
        Recording1155Receiver receiver = new Recording1155Receiver();
        vm.prank(alice);
        token.safeBatchTransferFrom(alice, address(receiver), _one(ID_1), _one(3), "batch-data");

        assertEq(uint8(receiver.lastHook()), uint8(Recording1155Receiver.Hook.Batch), "batch hook expected");
        assertEq(receiver.batchIdsLength(), 1);
        assertEq(receiver.lastData(), "batch-data");
        assertEq(token.balanceOf(address(receiver), ID_1), 3);
    }

    function test_SafeTransferFromCallsSingleHookWithData() public {
        Recording1155Receiver receiver = new Recording1155Receiver();
        vm.prank(alice);
        token.safeTransferFrom(alice, address(receiver), ID_1, 3, "single-data");

        assertEq(uint8(receiver.lastHook()), uint8(Recording1155Receiver.Hook.Single), "single hook expected");
        assertEq(receiver.lastData(), "single-data");
        assertEq(token.balanceOf(address(receiver), ID_1), 3);
    }

    function test_OneElementMintBatchCallsBatchHookWithData() public {
        Recording1155Receiver receiver = new Recording1155Receiver();
        helper.mintBatch(address(receiver), _one(ID_2), _one(7), "mint-batch-data");

        assertEq(uint8(receiver.lastHook()), uint8(Recording1155Receiver.Hook.Batch), "batch hook expected");
        assertEq(receiver.batchIdsLength(), 1);
        assertEq(receiver.lastData(), "mint-batch-data");
        assertEq(token.balanceOf(address(receiver), ID_2), 7);
    }

    function test_MintCallsSingleHookWithData() public {
        Recording1155Receiver receiver = new Recording1155Receiver();
        helper.mint(address(receiver), ID_2, 7, "mint-data");

        assertEq(uint8(receiver.lastHook()), uint8(Recording1155Receiver.Hook.Single), "single hook expected");
        assertEq(receiver.lastData(), "mint-data");
        assertEq(token.balanceOf(address(receiver), ID_2), 7);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  PAUSED
    //////////////////////////////////////////////////////////////////////////*//

    function test_PausedBlocksSafeTransferFrom() public {
        pausable.pause();
        vm.expectRevert(IPausable.EnforcedPause.selector);
        vm.prank(alice);
        token.safeTransferFrom(alice, bob, ID_1, 1, "");
    }

    function test_PausedBlocksSafeBatchTransferFrom() public {
        pausable.pause();
        vm.expectRevert(IPausable.EnforcedPause.selector);
        vm.prank(alice);
        token.safeBatchTransferFrom(alice, bob, _pair(ID_1, ID_2), _pair(1, 1), "");
    }

    function test_PausedBlocksBurn() public {
        pausable.pause();
        vm.expectRevert(IPausable.EnforcedPause.selector);
        vm.prank(alice);
        burnable.burn(alice, ID_1, 1);
    }

    function test_PausedBlocksBurnBatch() public {
        pausable.pause();
        vm.expectRevert(IPausable.EnforcedPause.selector);
        vm.prank(alice);
        burnable.burnBatch(alice, _pair(ID_1, ID_2), _pair(1, 1));
    }

    function test_PausedBlocksMint() public {
        pausable.pause();
        vm.expectRevert(IPausable.EnforcedPause.selector);
        helper.mint(bob, ID_1, 1, "");
    }

    function test_PausedBlocksMintBatch() public {
        pausable.pause();
        vm.expectRevert(IPausable.EnforcedPause.selector);
        helper.mintBatch(bob, _pair(ID_1, ID_2), _pair(1, 1), "");
    }

    /// @notice Approvals are not token movements, so OpenZeppelin leaves them open while paused.
    function test_PausedLeavesApprovalsOpen() public {
        pausable.pause();
        vm.prank(alice);
        token.setApprovalForAll(bob, true);
        assertTrue(token.isApprovedForAll(alice, bob));
    }

    function test_UnpauseRestoresMovement() public {
        pausable.pause();
        pausable.unpause();
        vm.prank(alice);
        token.safeTransferFrom(alice, bob, ID_1, 10, "");
        assertEq(token.balanceOf(bob, ID_1), 10);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    ERROR PRECEDENCE (OZ v5.6.1 `_update`)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice OpenZeppelin gates `_update`, so the authorization check still runs first while paused.
    function test_PausedUnauthorizedTransferRevertsMissingApproval() public {
        pausable.pause();
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155MissingApprovalForAll.selector, bob, alice));
        vm.prank(bob);
        token.safeTransferFrom(alice, bob, ID_1, 1, "");
    }

    /// @notice ...and so do the zero-address checks.
    function test_PausedTransferToZeroRevertsInvalidReceiver() public {
        pausable.pause();
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.safeBatchTransferFrom(alice, address(0), _pair(ID_1, ID_2), _pair(1, 1), "");
    }

    function test_PausedUnauthorizedBurnRevertsMissingApproval() public {
        pausable.pause();
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155MissingApprovalForAll.selector, bob, alice));
        vm.prank(bob);
        burnable.burnBatch(alice, _pair(ID_1, ID_2), _pair(1, 1));
    }

    function test_PausedMintToZeroRevertsInvalidReceiver() public {
        pausable.pause();
        vm.expectRevert(abi.encodeWithSelector(IERC1155.ERC1155InvalidReceiver.selector, address(0)));
        helper.mint(address(0), ID_1, 1, "");
    }

    /// @notice The pause check precedes the array-length check inside `_update`, as OpenZeppelin's modifier does.
    function test_PausedMismatchedArraysRevertsEnforcedPause() public {
        pausable.pause();
        uint256[] memory values = new uint256[](1);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        vm.prank(alice);
        token.safeBatchTransferFrom(alice, bob, _pair(ID_1, ID_2), values, "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               PAUSE AUTHORITY
    //////////////////////////////////////////////////////////////////////////*//

    function test_OnlyAdminCanPause() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, bytes32(0))
        );
        vm.prank(alice);
        pausable.pause();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IPausable).interfaceId));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC1155Burnable).interfaceId));
        assertTrue(ERC165Facet(diamond).supportsInterface(0xd9b67a26)); // IERC1155 (base)
    }
}
