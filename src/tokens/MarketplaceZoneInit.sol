// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {MarketplaceZoneLib} from "@lattice/tokens/libraries/MarketplaceZoneLib.sol";

/// @title MarketplaceZoneInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the Seaport {MarketplaceZone} recipe — grants `admin_` the DEFAULT_ADMIN_ROLE
///         that gates `setPaused`/`setRoyaltyRequired` and the `MARKETPLACE_BLOCKED_ROLE` grants, then registers
///         the Seaport `ZoneInterface` via ERC-165. Delegatecalled by {Diamond.initialize} inside the
///         initializing window (so it must NOT open its own pre/postInitializer; the `__*_init` guards pass
///         because the window is already open).
/// @custom:lattice-kind bundle
contract MarketplaceZoneInit {
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes MarketplaceZone;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;MarketplaceZone;
    /// @custom:lattice-param admin_ authority;
    /// @custom:lattice-registers-interfaces
    function init(address admin_) external {
        AccessControlLib.__AccessControl_init(admin_);
        MarketplaceZoneLib.__MarketplaceZone_init();
    }
}
