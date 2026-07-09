// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC2981Lib} from "@lattice/tokens/ERC2981/libraries/ERC2981Lib.sol";

/// @title ERC2981Init
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an ERC-2981 royalty diamond — registers the IERC2981 interface (ERC-165)
///         and seeds AccessControl so the royalty setters are admin-gated. Delegatecalled by
///         {Diamond.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer;
///         each `__*_init` guard passes because the window is already open). Companion to the {AccountInit} and
///         {ERC20Init} patterns — a first-class production deploy artifact.
contract ERC2981Init {
    /// @notice Runs the royalty + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the royalty setters).
    function init(address admin) external {
        AccessControlLib.__AccessControl_init(admin);
        ERC2981Lib.__ERC2981_init();
    }
}
