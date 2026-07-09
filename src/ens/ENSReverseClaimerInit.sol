// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ENSReverseClaimerLib} from "@lattice/ens/libraries/ENSReverseClaimerLib.sol";

/// @title ENSReverseClaimerInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an ENS reverse-claim diamond — seeds AccessControl (so the registrar setter
///         and `setEnsName` are `ENS_MANAGER_ROLE`-gated), registers the IENSReverseClaimer interface (ERC-165),
///         and wires the external ENS reverse registrar the facet forwards `setName` to. Delegatecalled by
///         {Diamond.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer;
///         each `__*_init` guard passes because the window is already open). Reverts
///         {ENSReverseClaimerZeroRegistrar} for a zero registrar.
contract ENSReverseClaimerInit {
    /// @notice Runs the ENS reverse-claimer + access-control module initializers. MUST be invoked via the
    ///         diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls role assignment).
    /// @param registrar The external ENS reverse registrar the facet forwards `setName` to.
    function init(address admin, address registrar) external {
        AccessControlLib.__AccessControl_init(admin);
        ENSReverseClaimerLib.__ENSReverseClaimer_init(registrar);
    }
}
