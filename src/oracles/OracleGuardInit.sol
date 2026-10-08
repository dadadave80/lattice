// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OracleGuardLib} from "@lattice/oracles/libraries/OracleGuardLib.sol";

/// @title OracleGuardInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the OracleGuard module: registers the IOracleGuard interface (ERC-165). It does
///         NOT seed AccessControl, so it composes (via {MultiInit}) next to the init that does: {AccessControlInit}
///         in the standalone {DeployOracleGuard} recipe, or an adapter's own init (for example
///         {ChainlinkAdapterInit}) when the guard is cut into a new adapter diamond. Delegatecalled by
///         {Diamond.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer;
///         the `__OracleGuard_init` guard passes because the window is already open). A cut adding the guard to an
///         already-initialized diamond calls `OracleGuardLib.__OracleGuard_init()` from its own reinitializer init.
contract OracleGuardInit {
    /// @notice Runs the OracleGuard module initializer. MUST be invoked via the diamond's `initialize` `_init`
    ///         delegatecall.
    function init() external {
        OracleGuardLib.__OracleGuard_init();
    }
}
