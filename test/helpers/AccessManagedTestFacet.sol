// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessManagedLib} from "@lattice/access/libraries/AccessManagedLib.sol";

/// @title AccessManagedTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet providing a concrete `restricted` entrypoint gated by {AccessManagedLib.restrictedCheck}
///         — the managed-target function that the external AccessManager authorizes (directly or via a matured
///         scheduled `execute`). Cut ON TOP of the production {DeployAccessManaged} recipe so the facet test can
///         exercise the full authority round-trip through the REAL diamond dispatch — never shipped.
contract AccessManagedTestFacet {
    /// @notice Reverts with `AccessManagedUnauthorized` unless the caller is authorized by the authority.
    function restrictedFn() external view {
        AccessManagedLib.restrictedCheck();
    }
}
