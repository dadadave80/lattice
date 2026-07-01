// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";

/// @title AccessControlTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet that exposes the internal {AccessControlLib} entrypoints the production `AccessControl`
///         facet deliberately does not surface: the admin-gated {AccessControlLib.setRoleAdmin} (there is no
///         public `setRoleAdmin` on the base facet) and a `restrictedFunction` demonstrating the `onlyRole`
///         gate via {AccessControlLib.checkRole}. Cut ON TOP of the production {DeployAccessControl} recipe so a
///         facet test can drive role-admin wiring and the role gate through the REAL diamond dispatch — never
///         shipped, never part of a `run()` deploy. Both revert exactly as their library does.
contract AccessControlTestFacet {
    bytes32 private constant RESTRICTED_ROLE = keccak256("RESTRICTED_ROLE");

    /// @notice Example gated function: reverts with `AccessControlUnauthorizedAccount` unless the caller holds
    ///         `RESTRICTED_ROLE`.
    function restrictedFunction() external view {
        AccessControlLib.checkRole(RESTRICTED_ROLE);
    }

    /// @notice Exposes the admin-gated {AccessControlLib.setRoleAdmin} (repoints a role's admin role).
    function setRoleAdminHelper(bytes32 role, bytes32 adminRole) external {
        AccessControlLib.setRoleAdmin(role, adminRole);
    }
}
