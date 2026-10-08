// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessManagedLib} from "@lattice/access/libraries/AccessManagedLib.sol";

/// @notice Callback a {AccessManagedTestFacet-restrictedNotify} caller receives once the gate has passed.
interface IAccessManagedTestHook {
    function onNotify() external;
}

/// @title AccessManagedTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet providing concrete managed-target entrypoints gated by {AccessManagedLib.restrictedCheck}
///         — the functions that the external AccessManager authorizes (directly or via a matured scheduled
///         `execute`). Cut ON TOP of the production {DeployAccessManaged} recipe so the facet test can exercise the
///         full authority round-trip through the REAL diamond dispatch — never shipped.
contract AccessManagedTestFacet {
    /// @notice Reverts with `AccessManagedUnauthorized` unless the caller is authorized by the authority.
    function restrictedFn() external {
        AccessManagedLib.restrictedCheck();
    }

    /// @notice Gated like {restrictedFn}, then calls out to `hook` — models a restricted function with an external
    ///         interaction (an ETH send, a token hook) so tests can prove a re-entrant callee gains no access.
    /// @param hook The contract notified after the gate passes.
    function restrictedNotify(address hook) external {
        AccessManagedLib.restrictedCheck();
        IAccessManagedTestHook(hook).onNotify();
    }
}
