// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {PausableTestBase} from "@lattice-test/base/PausableTestBase.sol";
import {PausableTestFacet} from "@lattice-test/helpers/PausableTestFacet.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {Pausable} from "@lattice/security/Pausable.sol";

/// @title PausableTest
/// @notice Exercises the Pausable facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployPausable} script (see {PausableTestBase}) — every call below routes through the diamond's
///         `delegatecall` dispatch, not a flattened inheritance mock. Admin gating is enforced by the cut-in
///         `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`; the `whenNotPaused`/
///         `whenPaused` guards by the appended test-only {PausableTestFacet}.
contract PausableTest is PausableTestBase {
    address internal admin = address(0xA1);
    address internal nonAdmin = address(0xB2);

    function setUp() public {
        diamond = _deployPausable(admin);
        pausable = Pausable(diamond);
        guard = PausableTestFacet(diamond);
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    function test_InitiallyNotPaused() public view {
        assertFalse(pausable.paused());
    }

    function test_ERC165RegisteredIPausable() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IPausable).interfaceId));
    }

    // -------------------------------------------------------------------------
    // pause()
    // -------------------------------------------------------------------------

    function test_PauseFlipsState() public {
        vm.prank(admin);
        pausable.pause();
        assertTrue(pausable.paused());
    }

    function test_PauseEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IPausable.Paused(admin);
        pausable.pause();
    }

    function test_PauseRevertsForNonAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, DEFAULT_ADMIN_ROLE
            )
        );
        pausable.pause();
    }

    function test_DoublePauseRevertsEnforcedPause() public {
        vm.prank(admin);
        pausable.pause();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPausable.EnforcedPause.selector));
        pausable.pause();
    }

    // -------------------------------------------------------------------------
    // unpause()
    // -------------------------------------------------------------------------

    function test_UnpauseFlipsState() public {
        vm.prank(admin);
        pausable.pause();

        vm.prank(admin);
        pausable.unpause();
        assertFalse(pausable.paused());
    }

    function test_UnpauseEmitsEvent() public {
        vm.prank(admin);
        pausable.pause();

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IPausable.Unpaused(admin);
        pausable.unpause();
    }

    function test_UnpauseRevertsForNonAdmin() public {
        vm.prank(admin);
        pausable.pause();

        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, DEFAULT_ADMIN_ROLE
            )
        );
        pausable.unpause();
    }

    function test_UnpauseWhenNotPausedRevertsExpectedPause() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPausable.ExpectedPause.selector));
        pausable.unpause();
    }

    function test_DoubleUnpauseRevertsExpectedPause() public {
        vm.prank(admin);
        pausable.pause();

        vm.prank(admin);
        pausable.unpause();

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPausable.ExpectedPause.selector));
        pausable.unpause();
    }

    // -------------------------------------------------------------------------
    // whenNotPaused / whenPaused gates
    // -------------------------------------------------------------------------

    function test_GatedActionSucceedsWhenNotPaused() public view {
        guard.gatedAction(); // should not revert
    }

    function test_GatedActionRevertsWhenPaused() public {
        vm.prank(admin);
        pausable.pause();

        vm.expectRevert(abi.encodeWithSelector(IPausable.EnforcedPause.selector));
        guard.gatedAction();
    }

    function test_PausedOnlyActionSucceedsWhenPaused() public {
        vm.prank(admin);
        pausable.pause();
        guard.pausedOnlyAction(); // should not revert
    }

    function test_PausedOnlyActionRevertsWhenNotPaused() public {
        vm.expectRevert(abi.encodeWithSelector(IPausable.ExpectedPause.selector));
        guard.pausedOnlyAction();
    }

    // -------------------------------------------------------------------------
    // Pause / unpause cycle
    // -------------------------------------------------------------------------

    function test_PauseUnpauseCycle() public {
        vm.prank(admin);
        pausable.pause();
        assertTrue(pausable.paused());

        vm.prank(admin);
        pausable.unpause();
        assertFalse(pausable.paused());

        vm.prank(admin);
        pausable.pause();
        assertTrue(pausable.paused());
    }

    // -------------------------------------------------------------------------
    // OZ-reconciliation: P-1 — explicit _paused = false in init
    // -------------------------------------------------------------------------

    /// @notice Verifies that the initializer leaves the paused state explicitly false,
    /// matching OZ v5.1.0's defensive `_paused = false` write in the constructor.
    function test_PauseInitialStateIsExplicitlyFalse() public view {
        // After setUp() the diamond is freshly initialised. The state must be false.
        assertFalse(pausable.paused());
    }
}
