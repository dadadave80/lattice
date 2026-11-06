// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ENSResolverLib} from "@lattice/ens/libraries/ENSResolverLib.sol";

/// @title ENSResolverInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an ENS forward-resolution diamond — seeds AccessControl (so the registry
///         setter is `ENS_MANAGER_ROLE`-gated), registers the IENSResolver interface (ERC-165), and wires the
///         external ENS registry the facet reads resolvers from. Delegatecalled by {Lattice.initialize} inside
///         the initializing window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes
///         because the window is already open). Reverts {ENSResolverZeroRegistry} for a zero registry.
/// @custom:lattice-kind bundle
contract ENSResolverInit {
    /// @notice Runs the ENS resolver + access-control module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls role assignment).
    /// @param registry The external ENS registry the facet reads resolvers from.
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes ENSResolver;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;ENSResolver;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-param registry;
    /// @custom:lattice-registers-interfaces
    function init(address admin, address registry) external {
        AccessControlLib.__AccessControl_init(admin);
        ENSResolverLib.__ENSResolver_init(registry);
    }
}
