// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IInvariantChecker} from "@lattice/interfaces/security/IInvariantChecker.sol";
import {InvariantCheckerLib} from "@lattice/security/libraries/InvariantCheckerLib.sol";

/// @title InvariantChecker
/// @notice Thin Diamond facet that exposes a registry of named on-chain invariants.
/// @dev All logic lives in {InvariantCheckerLib}. This contract is stateless and forwards
///      every call to the library. Inherit this in your Diamond facet to add invariant checking.
///
///      Opt-in safety facet. Lattice ships no default invariants because it ships no protocol
///      of its own — the checker is a generic primitive that consumers wire to *their* invariants.
///      The pattern is:
///        1. Expose a `bool`-returning `view` on your protocol (e.g. `isSolvent()` returning
///           `backing >= liabilities`).
///        2. Governance (`DEFAULT_ADMIN_ROLE`) calls {registerInvariant} with a key, the target
///           contract, and that view's selector.
///        3. Gate sensitive operations on {checkInvariant} / {checkInvariants}; they `staticcall`
///           the registered view and revert (`InvariantViolatedError`) if it returns `false`, or
///           (`InvariantCheckFailed`) if the call itself reverts.
///      The check tracks live state — it is not a one-shot latch — so the gate re-opens once the
///      invariant holds again. See `test/unit/InvariantCheckerUsageTester.t.sol` for the canonical
///      worked example (a solvency invariant: registration, happy path, violation path, batch).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract InvariantChecker is IInvariantChecker {
    /// @inheritdoc IInvariantChecker
    function getInvariant(bytes32 key) public view virtual returns (address target, bytes4 selector) {
        return InvariantCheckerLib.getInvariant(key);
    }

    /// @inheritdoc IInvariantChecker
    function registerInvariant(bytes32 key, address target, bytes4 selector) public virtual {
        InvariantCheckerLib.registerInvariant(key, target, selector);
    }

    /// @inheritdoc IInvariantChecker
    function unregisterInvariant(bytes32 key) public virtual {
        InvariantCheckerLib.unregisterInvariant(key);
    }

    /// @inheritdoc IInvariantChecker
    function checkInvariant(bytes32 key) public view virtual {
        InvariantCheckerLib.checkInvariant(key);
    }

    /// @inheritdoc IInvariantChecker
    function checkInvariants(bytes32[] calldata keys) public view virtual {
        InvariantCheckerLib.checkInvariants(keys);
    }
}
