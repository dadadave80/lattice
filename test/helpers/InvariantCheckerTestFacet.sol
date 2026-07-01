// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InvariantCheckerLib} from "@lattice/security/libraries/InvariantCheckerLib.sol";

/// @title InvariantCheckerTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet cut ON TOP of the {DeployInvariantChecker} recipe to make the opt-in usage pattern
///         executable on a REAL diamond. `distributeYield` is the canonical "consumer gates a sensitive action on
///         a registered invariant" example (see `test/unit/InvariantCheckerUsageTest.t.sol`): it forwards to
///         {InvariantCheckerLib.checkInvariant}, so the whole flow — register (admin-gated), pass, revert on
///         violation — is exercised through the diamond's `delegatecall` dispatch. Never shipped, never part of a
///         `run()` deploy.
contract InvariantCheckerTestFacet {
    /// @notice A sensitive action gated on a consumer-registered invariant: reverts (via InvariantChecker) if the
    ///         invariant `key` does not hold. Mirrors how a real protocol asserts its own invariant before doing
    ///         state-changing work.
    /// @param key The invariant key to assert before proceeding.
    function distributeYield(bytes32 key) external view {
        InvariantCheckerLib.checkInvariant(key);
        // ... a real protocol would perform the distribution here ...
    }
}
