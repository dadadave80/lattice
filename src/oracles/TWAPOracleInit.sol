// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {TWAPOracleLib} from "@lattice/oracles/libraries/TWAPOracleLib.sol";

/// @title TWAPOracleInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a TWAPOracle diamond — grants `DEFAULT_ADMIN_ROLE` to `admin` (pair
///         registration is admin-gated; observation recording is permissionless) and registers ITWAPOracle via
///         ERC-165. Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open
///         its own pre/postInitializer; each `__*_init` guard passes because the window is already open).
///         Companion to the {ERC2981Init}/{VaultCoreInit} patterns — a first-class production deploy artifact.
contract TWAPOracleInit {
    /// @notice Runs the access-control + TWAPOracle module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        TWAPOracleLib.__TWAPOracle_init();
    }
}
