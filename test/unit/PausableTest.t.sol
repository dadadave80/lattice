// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title MockPausableContract
/// @notice Test double combining Pausable + AccessControl with an external gate function.
contract MockPausableContract is Pausable, AccessControl {
    /// @notice Initializes both AccessControl and Pausable modules.
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        PausableLib.__Pausable_init();
        InitializableLib.postInitializer(s);
    }

    /// @notice External function that reverts when paused (tests `whenNotPaused` gate).
    function gatedAction() external view {
        PausableLib.whenNotPaused();
    }

    /// @notice External function that reverts when NOT paused (tests `whenPaused` gate).
    function pausedOnlyAction() external view {
        PausableLib.whenPaused();
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title PausableTest
/// @notice Comprehensive tests for the Pausable module.
contract PausableTest is Test {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;

    MockPausableContract internal mock;
    address internal admin = address(0xA1);
    address internal nonAdmin = address(0xB2);

    function setUp() public {
        mock = new MockPausableContract();
        mock.initialize(admin);
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    function test_InitiallyNotPaused() public view {
        assertFalse(mock.paused());
    }

    function test_ERC165RegisteredIPausable() public view {
        assertTrue(mock.supportsInterface(type(IPausable).interfaceId));
    }

    // -------------------------------------------------------------------------
    // pause()
    // -------------------------------------------------------------------------

    function test_PauseFlipsState() public {
        vm.prank(admin);
        mock.pause();
        assertTrue(mock.paused());
    }

    function test_PauseEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(admin);
        mock.pause();
    }

    function test_PauseRevertsForNonAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, DEFAULT_ADMIN_ROLE
            )
        );
        mock.pause();
    }

    function test_DoublePauseRevertsEnforcedPause() public {
        vm.prank(admin);
        mock.pause();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPausable.EnforcedPause.selector));
        mock.pause();
    }

    // -------------------------------------------------------------------------
    // unpause()
    // -------------------------------------------------------------------------

    function test_UnpauseFlipsState() public {
        vm.prank(admin);
        mock.pause();

        vm.prank(admin);
        mock.unpause();
        assertFalse(mock.paused());
    }

    function test_UnpauseEmitsEvent() public {
        vm.prank(admin);
        mock.pause();

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IPausable.Unpaused(admin);
        mock.unpause();
    }

    function test_UnpauseRevertsForNonAdmin() public {
        vm.prank(admin);
        mock.pause();

        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, DEFAULT_ADMIN_ROLE
            )
        );
        mock.unpause();
    }

    function test_UnpauseWhenNotPausedRevertsExpectedPause() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPausable.ExpectedPause.selector));
        mock.unpause();
    }

    function test_DoubleUnpauseRevertsExpectedPause() public {
        vm.prank(admin);
        mock.pause();

        vm.prank(admin);
        mock.unpause();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPausable.ExpectedPause.selector));
        mock.unpause();
    }

    // -------------------------------------------------------------------------
    // whenNotPaused / whenPaused gates
    // -------------------------------------------------------------------------

    function test_GatedActionSucceedsWhenNotPaused() public view {
        mock.gatedAction(); // should not revert
    }

    function test_GatedActionRevertsWhenPaused() public {
        vm.prank(admin);
        mock.pause();

        vm.expectRevert(abi.encodeWithSelector(IPausable.EnforcedPause.selector));
        mock.gatedAction();
    }

    function test_PausedOnlyActionSucceedsWhenPaused() public {
        vm.prank(admin);
        mock.pause();
        mock.pausedOnlyAction(); // should not revert
    }

    function test_PausedOnlyActionRevertsWhenNotPaused() public {
        vm.expectRevert(abi.encodeWithSelector(IPausable.ExpectedPause.selector));
        mock.pausedOnlyAction();
    }

    // -------------------------------------------------------------------------
    // Pause / unpause cycle
    // -------------------------------------------------------------------------

    function test_PauseUnpauseCycle() public {
        vm.prank(admin);
        mock.pause();
        assertTrue(mock.paused());

        vm.prank(admin);
        mock.unpause();
        assertFalse(mock.paused());

        vm.prank(admin);
        mock.pause();
        assertTrue(mock.paused());
    }

    // -------------------------------------------------------------------------
    // OZ-reconciliation: P-1 — explicit _paused = false in init
    // -------------------------------------------------------------------------

    /// @notice Verifies that the initializer leaves the paused state explicitly false,
    /// matching OZ v5.1.0's defensive `_paused = false` write in the constructor.
    function test_PauseInitialStateIsExplicitlyFalse() public view {
        // After setUp() the contract is freshly initialised. The state must be false.
        assertFalse(mock.paused());
    }
}
