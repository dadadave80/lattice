// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ChainlinkVRFLib} from "@lattice/oracles/chainlink/ChainlinkVRFLib.sol";

/// @title ChainlinkVRFInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Chainlink VRF randomness diamond — seeds AccessControl so the VRF
///         config + request setters are admin-gated, and registers the IChainlinkVRF interface (ERC-165).
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open). Companion to
///         the {ERC2981Init} pattern — a first-class production deploy artifact.
contract ChainlinkVRFInit {
    /// @notice Runs the VRF + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the VRF config + request setters).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        ChainlinkVRFLib.__ChainlinkVRF_init();
    }
}
