// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {API3AdapterLib} from "@lattice/oracles/libraries/API3AdapterLib.sol";

/// @title API3AdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an API3 dAPI price-feed adapter diamond — seeds AccessControl (so the feed
///         registry setters are admin-gated) and registers the IAPI3Adapter interface (ERC-165). Delegatecalled
///         by {Diamond.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer;
///         each `__*_init` guard passes because the window is already open). dAPI proxies are registered later via
///         `registerFeed`, so no external reference is needed at init time.
contract API3AdapterInit {
    /// @notice Runs the API3 adapter + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        API3AdapterLib.__API3Adapter_init();
    }
}
