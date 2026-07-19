// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {ERC165_MAP_IPAUSABLE_SLOT, PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Consumer-shape mock: the {Pausable} facade's `whenNotPaused`/`whenPaused` modifiers over the lib.
contract PausableMock is Pausable, Initializable {
    uint256 public actions;

    function initialize(address _admin) external initializer {
        AccessControlLib.__AccessControl_init(_admin);
        PausableLib.__Pausable_init();
    }

    function guardedAction() external whenNotPaused {
        ++actions;
    }

    function emergencyDrain() external whenPaused {
        ++actions;
    }

    /// @dev Exposes the renamed lib check directly (facets that guard without inheriting the facade).
    function checkDirect() external view {
        PausableLib.checkNotPaused();
    }
}

contract PausableMixinTest is Test {
    PausableMock internal mock;

    function setUp() public {
        mock = new PausableMock();
        mock.initialize(address(this));
    }

    function test_InitRegistersIPausableInterface() public view {
        assertEq(vm.load(address(mock), ERC165_MAP_IPAUSABLE_SLOT), bytes32(uint256(1)));
    }

    function test_GuardedActionWorksWhenNotPaused() public {
        mock.guardedAction();
        assertEq(mock.actions(), 1);
        mock.checkDirect();
    }

    function test_WhenPausedRevertsWhileNotPaused() public {
        vm.expectRevert(IPausable.ExpectedPause.selector);
        mock.emergencyDrain();
    }

    function test_PauseBlocksGuardedAndOpensPausedOnly() public {
        mock.pause();
        assertTrue(mock.paused());
        vm.expectRevert(IPausable.EnforcedPause.selector);
        mock.guardedAction();
        vm.expectRevert(IPausable.EnforcedPause.selector);
        mock.checkDirect();
        mock.emergencyDrain();
        assertEq(mock.actions(), 1);
    }

    function test_UnpauseRestoresGuarded() public {
        mock.pause();
        mock.unpause();
        assertFalse(mock.paused());
        mock.guardedAction();
        assertEq(mock.actions(), 1);
        vm.expectRevert(IPausable.ExpectedPause.selector);
        mock.emergencyDrain();
    }
}
