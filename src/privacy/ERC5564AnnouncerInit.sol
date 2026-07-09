// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC5564AnnouncerLib} from "@lattice/privacy/libraries/ERC5564AnnouncerLib.sol";

/// @title ERC5564AnnouncerInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an ERC-5564 stealth-address announcer diamond — registers the
///         IERC5564Announcer interface (ERC-165). Delegatecalled by {Diamond.initialize} inside the initializing
///         window (so it must NOT open its own pre/postInitializer; the `__ERC5564Announcer_init` guard passes
///         because the window is already open). The announcer is permissionless, so no AccessControl is seeded.
contract ERC5564AnnouncerInit {
    /// @notice Runs the announcer module initializer. MUST be invoked via the diamond's `initialize`
    ///         `_init` delegatecall.
    function init() external {
        ERC5564AnnouncerLib.__ERC5564Announcer_init();
    }
}
