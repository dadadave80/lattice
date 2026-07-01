// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ChainlinkAdapterLib} from "@lattice/oracles/libraries/ChainlinkAdapterLib.sol";

/// @title ChainlinkAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Chainlink price-feed adapter diamond — seeds AccessControl (so the feed
///         registry setters are admin-gated) and registers the IChainlinkAdapter interface (ERC-165).
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open). Feeds are
///         registered later via `registerFeed`, so no external reference is needed at init time.
contract ChainlinkAdapterInit {
    /// @notice Runs the Chainlink adapter + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        ChainlinkAdapterLib.__ChainlinkAdapter_init();
    }
}
