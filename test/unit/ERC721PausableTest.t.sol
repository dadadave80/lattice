// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC721Pausable} from "@lattice-script/base/tokens/DeployERC721Pausable.s.sol";
import {ERC721TestBase} from "@lattice-test/base/ERC721TestBase.sol";
import {ERC721TestFacet} from "@lattice-test/helpers/ERC721TestFacet.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721Pausable} from "@lattice/tokens/ERC721/ERC721Pausable.sol";

/// @title ERC721PausableTest
/// @notice Exercises the {ERC721Pausable} facet through a REAL diamond assembled by the {DeployERC721Pausable}
///         recipe: base ERC-721, the {Pausable} facet (admin-gated `pause()`/`unpause()`), and {ERC721Pausable},
///         which REPLACES `transferFrom` and both `safeTransferFrom` overloads with pause-gated variants. The test
///         contract is the pause authority; the test-only {ERC721TestFacet} seeds tokens.
contract ERC721PausableTest is ERC721TestBase {
    Pausable internal pausable;

    address admin = address(this);
    address alice = address(0x1);
    address bob = address(0x2);

    uint256 constant TOKEN_1 = 1;
    uint256 constant TOKEN_2 = 2;

    function setUp() public override {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            new DeployERC721Pausable().buildCuts("Pause NFT", "PNFT", admin);
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC721(diamond);
        helper = ERC721TestFacet(diamond);
        pausable = Pausable(diamond);

        helper.mint(alice, TOKEN_1);
        helper.mint(alice, TOKEN_2);
    }

    function test_SupportsInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IPausable).interfaceId), "IPausable");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x80ac58cd), "EIP-721");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x5b5e139f), "EIP-721 metadata");
    }

    /// @notice The recipe routes all three movement selectors to the pausable facet.
    function test_RecipeReplacesEveryMovementSelector() public view {
        address facet = IDiamondLoupe(diamond).facetAddress(ERC721Pausable.transferFrom.selector);
        assertTrue(facet != IDiamondLoupe(diamond).facetAddress(IERC721.approve.selector), "not the base facet");
        assertEq(IDiamondLoupe(diamond).facetAddress(0x42842e0e), facet, "safeTransferFrom(3)");
        assertEq(IDiamondLoupe(diamond).facetAddress(0xb88d4fde), facet, "safeTransferFrom(4)");
    }

    function test_TransfersWorkWhenNotPaused() public {
        vm.startPrank(alice);
        token.transferFrom(alice, bob, TOKEN_1);
        token.safeTransferFrom(alice, bob, TOKEN_2);
        vm.stopPrank();
        assertEq(token.balanceOf(bob), 2);
        assertEq(token.ownerOf(TOKEN_1), bob);
        assertEq(token.ownerOf(TOKEN_2), bob);
    }

    function test_PausedBlocksTransferFrom() public {
        pausable.pause();
        vm.prank(alice);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        token.transferFrom(alice, bob, TOKEN_1);
    }

    function test_PausedBlocksSafeTransferFrom() public {
        pausable.pause();
        vm.prank(alice);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        token.safeTransferFrom(alice, bob, TOKEN_1);
    }

    function test_PausedBlocksSafeTransferFromWithData() public {
        pausable.pause();
        vm.prank(alice);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        token.safeTransferFrom(alice, bob, TOKEN_1, "data");
    }

    /// @notice OpenZeppelin gates `_update`, not approvals: approving while paused still works.
    function test_PausedStillAllowsApprovals() public {
        pausable.pause();
        vm.startPrank(alice);
        token.approve(bob, TOKEN_1);
        token.setApprovalForAll(bob, true);
        vm.stopPrank();
        assertEq(token.getApproved(TOKEN_1), bob);
        assertTrue(token.isApprovedForAll(alice, bob));
    }

    function test_UnpauseRestoresTransfers() public {
        pausable.pause();
        pausable.unpause();
        vm.prank(alice);
        token.transferFrom(alice, bob, TOKEN_1);
        assertEq(token.ownerOf(TOKEN_1), bob);
    }

    function test_OnlyAdminPauses() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, bytes32(0))
        );
        pausable.pause();
    }

    /// @notice A mint through {ERC721Lib} is not a facet selector, so the pause does not gate it (a behaviour
    ///         difference from OpenZeppelin, which pauses mints and burns in `_update`).
    function test_LibraryMintIsNotGatedByPause() public {
        pausable.pause();
        helper.mint(bob, 3);
        assertEq(token.ownerOf(3), bob);
    }
}
