// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Pausable} from "@lattice/tokens/ERC20/ERC20Pausable.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockERC20PausableContract
/// @notice Composes the ERC20Pausable facet (transfer gating) with the Pausable facet (pause/unpause control)
///         and AccessControl (admin auth for pause), as a real token diamond would.
contract MockERC20PausableContract is ERC20, ERC20Pausable, Pausable {
    function transfer(address to, uint256 value) public override(ERC20, ERC20Pausable) returns (bool) {
        return ERC20Pausable.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value)
        public
        override(ERC20, ERC20Pausable)
        returns (bool)
    {
        return ERC20Pausable.transferFrom(from, to, value);
    }

    function initialize(string memory name_, string memory symbol_, address admin, address mintTo, uint256 mintAmount)
        external
    {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init(name_, symbol_);
        PausableLib.__Pausable_init();
        AccessControlLib.__AccessControl_init(admin);
        if (mintTo != address(0) && mintAmount > 0) {
            ERC20Lib._mint(mintTo, mintAmount);
        }
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC20PausableTester
/// @notice ERC20 batch (token-extension completion): pausable transfers via the shared PausableLib.
contract ERC20PausableTester is Test {
    MockERC20PausableContract token;

    address admin = address(this);
    address alice = address(0x1);
    address bob = address(0x2);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    function setUp() public {
        token = new MockERC20PausableContract();
        token.initialize("Pause Token", "PAUSE", admin, alice, INITIAL_SUPPLY);
    }

    function test_TransferWorksWhenNotPaused() public {
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - 100e18);
    }

    function test_PausedBlocksTransfer() public {
        token.pause();
        assertTrue(token.paused());
        vm.prank(alice);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        token.transfer(bob, 100e18);
    }

    function test_PausedBlocksTransferFrom() public {
        vm.prank(alice);
        token.approve(bob, 100e18);
        token.pause();
        vm.prank(bob);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        token.transferFrom(alice, bob, 100e18);
    }

    function test_UnpauseRestoresTransfer() public {
        token.pause();
        token.unpause();
        assertFalse(token.paused());
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }
}
