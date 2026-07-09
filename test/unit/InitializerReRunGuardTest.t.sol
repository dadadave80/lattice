// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib, InvalidInitialization} from "@diamond/libraries/InitializableLib.sol";
import {DiamondValidationLib} from "@lattice/governance/libraries/DiamondValidationLib.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockInitializable
/// @notice Minimal consumer of diamond-lib `InitializableLib` that demonstrates OZ-style re-run
///         protection: a plain `initializer()`-guarded `initialize` runs once, and a
///         `reinitializer(version)`-guarded `upgradeTo` requires a strictly increasing version.
/// @dev Uses the real `preInitializer`/`postInitializer`/`preReinitializer`/`postReinitializer`
///      manual dance (the modifiers compile to these calls) so the proof exercises the on-chain
///      runtime guard, not a test-only re-implementation.
contract MockInitializable {
    /// @notice Set during init to prove the body actually ran (mirrors a critical config write).
    address public admin;

    /// @notice v1 initializer — guarded like OZ `initializer()`. Reverts on a second call.
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        admin = _admin;
        InitializableLib.postInitializer(s);
    }

    /// @notice Upgrade hook — guarded like OZ `reinitializer(_version)`. Requires `_version` to be
    ///         strictly greater than the current initialized version.
    function upgradeTo(uint64 _version, address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preReinitializer(s, _version);
        admin = _admin;
        InitializableLib.postReinitializer(s, _version);
    }

    /// @notice Exposes the current initialized version for assertions.
    function initializedVersion() external view returns (uint64) {
        return InitializableLib.getInitializedVersion(InitializableLib.initializableSlot());
    }
}

/// @title InitializerReRunGuardTest
/// @notice Executable proof of initializer re-run protection plus unit tests for the pure pre-flight
///         `DiamondValidationLib.assertReinitializerMonotonic` check that an upgrade workflow runs
///         before broadcasting a cut that carries an `_init`.
contract InitializerReRunGuardTest is Test {
    MockInitializable internal mock;

    address internal adminA = address(0xA1);
    address internal adminB = address(0xB2);
    address internal adminC = address(0xC3);

    function setUp() public {
        mock = new MockInitializable();
    }

    /// @dev External wrapper so vm.expectRevert can target the internal library call via a frame.
    function callAssertMonotonic(uint64 deployedVersion, uint64 cutInitVersion) external pure {
        DiamondValidationLib.assertReinitializerMonotonic(deployedVersion, cutInitVersion);
    }

    // -------------------------------------------------------------------------
    // (a) Plain initializer() runs once and reverts on a second call.
    // -------------------------------------------------------------------------

    function test_InitializeRunsOnce() public {
        mock.initialize(adminA);
        assertEq(mock.admin(), adminA);
        assertEq(mock.initializedVersion(), 1);
    }

    function test_SecondInitializeReverts() public {
        mock.initialize(adminA);
        vm.expectRevert(InvalidInitialization.selector);
        mock.initialize(adminB);
        // Critical state (admin) is NOT reset by the rejected re-run.
        assertEq(mock.admin(), adminA);
    }

    // -------------------------------------------------------------------------
    // (b) reinitializer(v) requires a strictly increasing version.
    // -------------------------------------------------------------------------

    function test_ReinitializerRequiresStrictlyIncreasingVersion() public {
        mock.initialize(adminA); // version => 1
        mock.upgradeTo(2, adminB); // 2 > 1 OK
        assertEq(mock.initializedVersion(), 2);
        assertEq(mock.admin(), adminB);
    }

    function test_ReinitializerRejectsSameVersion() public {
        mock.initialize(adminA); // version => 1
        mock.upgradeTo(2, adminB); // version => 2
        vm.expectRevert(InvalidInitialization.selector);
        mock.upgradeTo(2, adminC); // re-run same version => reject
        assertEq(mock.admin(), adminB);
    }

    function test_ReinitializerRejectsLowerVersion() public {
        mock.initialize(adminA); // version => 1
        mock.upgradeTo(3, adminB); // version => 3
        vm.expectRevert(InvalidInitialization.selector);
        mock.upgradeTo(2, adminC); // lower than current => reject
        assertEq(mock.admin(), adminB);
    }

    /// @dev Re-running the v1 `initializer()` after the Diamond is live (the exact attack in scope)
    ///      is rejected because the contract already has code and version == 1.
    function test_ReinitializerCannotReplayVersionOne() public {
        mock.initialize(adminA); // version => 1
        vm.expectRevert(InvalidInitialization.selector);
        mock.upgradeTo(1, adminC); // not strictly greater than 1 => reject
        assertEq(mock.admin(), adminA);
    }

    // -------------------------------------------------------------------------
    // (c) getInitializedVersion reports the current version.
    // -------------------------------------------------------------------------

    function test_GetInitializedVersionTracksUpgrades() public {
        assertEq(mock.initializedVersion(), 0); // never initialized
        mock.initialize(adminA);
        assertEq(mock.initializedVersion(), 1);
        mock.upgradeTo(5, adminB);
        assertEq(mock.initializedVersion(), 5);
    }

    // -------------------------------------------------------------------------
    // (d) assertReinitializerMonotonic pre-flight: rejects non-increasing, passes increasing.
    // -------------------------------------------------------------------------

    function test_AssertMonotonicPassesForIncreasingVersion() public view {
        this.callAssertMonotonic(1, 2); // 2 > 1
        this.callAssertMonotonic(0, 1); // 1 > 0
        this.callAssertMonotonic(5, type(uint64).max); // strictly greater
    }

    function test_AssertMonotonicRevertsForEqualVersion() public {
        vm.expectRevert(abi.encodeWithSelector(DiamondValidationLib.InitializerWouldReRun.selector, 2, 2));
        this.callAssertMonotonic(2, 2);
    }

    function test_AssertMonotonicRevertsForLowerVersion() public {
        vm.expectRevert(abi.encodeWithSelector(DiamondValidationLib.InitializerWouldReRun.selector, 3, 2));
        this.callAssertMonotonic(3, 2);
    }

    function test_AssertMonotonicRevertsForZeroAgainstZero() public {
        vm.expectRevert(abi.encodeWithSelector(DiamondValidationLib.InitializerWouldReRun.selector, 0, 0));
        this.callAssertMonotonic(0, 0);
    }

    /// @notice End-to-end: the pre-flight check agrees with the runtime guard. A cut init version
    ///         that passes `assertReinitializerMonotonic` against the live version also succeeds at
    ///         runtime; one that fails the pre-flight also reverts at runtime.
    function test_PreflightAgreesWithRuntimeGuard() public {
        mock.initialize(adminA); // live version => 1
        uint64 deployed = mock.initializedVersion();

        // Pre-flight passes for v2, and the runtime cut succeeds.
        this.callAssertMonotonic(deployed, 2);
        mock.upgradeTo(2, adminB);
        assertEq(mock.initializedVersion(), 2);

        // Pre-flight rejects replaying v2; the runtime cut would also revert.
        deployed = mock.initializedVersion();
        vm.expectRevert(abi.encodeWithSelector(DiamondValidationLib.InitializerWouldReRun.selector, deployed, 2));
        this.callAssertMonotonic(deployed, 2);
        vm.expectRevert(InvalidInitialization.selector);
        mock.upgradeTo(2, adminC);
        assertEq(mock.admin(), adminB);
    }
}
