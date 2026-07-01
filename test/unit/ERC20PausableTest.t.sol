// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20Pausable} from "@lattice-script/base/DeployERC20Pausable.s.sol";
import {ERC20TestBase} from "@lattice-test/base/ERC20TestBase.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";

/// @title ERC20PausableTest
/// @notice Exercises the {ERC20Pausable} facet (pause-gated transfers) through a REAL {Diamond} assembled by the
///         ready-to-deploy {DeployERC20Pausable} script: base ERC-20, the {Pausable} facet (admin-gated
///         `pause()`/`unpause()`), and {ERC20Pausable} which REPLACES `transfer`/`transferFrom` with pause-gated
///         variants. The pause authority (DEFAULT_ADMIN_ROLE) is this test contract; the initial supply is seeded
///         via the test-only {TokenTestFacet} (`helper`). Every call routes through the diamond's dispatch.
contract ERC20PausableTest is ERC20TestBase {
    Pausable internal pausable;

    address admin = address(this);
    address alice = address(0x1);
    address bob = address(0x2);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    function setUp() public override {
        DeployERC20Pausable d = new DeployERC20Pausable();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            d.buildCuts("Pause Token", "PAUSE", admin);
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC20(diamond);
        helper = TokenTestFacet(diamond);
        pausable = Pausable(diamond);

        helper.mint(alice, INITIAL_SUPPLY);
    }

    function test_TransferWorksWhenNotPaused() public {
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - 100e18);
    }

    function test_PausedBlocksTransfer() public {
        pausable.pause();
        assertTrue(pausable.paused());
        vm.prank(alice);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        token.transfer(bob, 100e18);
    }

    function test_PausedBlocksTransferFrom() public {
        vm.prank(alice);
        token.approve(bob, 100e18);
        pausable.pause();
        vm.prank(bob);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        token.transferFrom(alice, bob, 100e18);
    }

    function test_UnpauseRestoresTransfer() public {
        pausable.pause();
        pausable.unpause();
        assertFalse(pausable.paused());
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }
}
