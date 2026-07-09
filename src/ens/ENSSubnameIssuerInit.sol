// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ENSSubnameIssuerLib} from "@lattice/ens/libraries/ENSSubnameIssuerLib.sol";

/// @title ENSSubnameIssuerInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an ENS subname-issuer diamond — seeds AccessControl (so `issueSubname` and the
///         wrapper setter are `ENS_SUBNAME_ISSUER_ROLE`-gated), registers the IENSSubnameIssuer interface
///         (ERC-165), and wires the external ENS NameWrapper the facet forwards `setSubnodeRecord` to.
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open). Reverts
///         {ENSSubnameIssuerZeroNameWrapper} for a zero wrapper.
contract ENSSubnameIssuerInit {
    /// @notice Runs the ENS subname-issuer + access-control module initializers. MUST be invoked via the
    ///         diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls role assignment).
    /// @param wrapper The external ENS NameWrapper the facet forwards `setSubnodeRecord` to.
    function init(address admin, address wrapper) external {
        AccessControlLib.__AccessControl_init(admin);
        ENSSubnameIssuerLib.__ENSSubnameIssuer_init(wrapper);
    }
}
