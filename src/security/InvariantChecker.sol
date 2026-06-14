// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IInvariantChecker} from "@lattice/interfaces/IInvariantChecker.sol";
import {InvariantCheckerLib} from "@lattice/security/libraries/InvariantCheckerLib.sol";

/// @title InvariantChecker
/// @notice Thin Diamond facet that exposes a registry of named on-chain invariants.
/// @dev All logic lives in {InvariantCheckerLib}. This contract is stateless and forwards
///      every call to the library. Inherit this in your Diamond facet to add invariant checking.
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
