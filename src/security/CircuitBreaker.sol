// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICircuitBreaker} from "@lattice/interfaces/security/ICircuitBreaker.sol";
import {CircuitBreakerLib} from "@lattice/security/libraries/CircuitBreakerLib.sol";

/// @title CircuitBreaker
/// @notice Thin Diamond facet that exposes multi-key threshold-based circuit breaking.
/// @dev All logic lives in {CircuitBreakerLib}. This contract is stateless and forwards
///      every call to the library. Inherit this in your Diamond facet to add circuit-breaking.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract CircuitBreaker is ICircuitBreaker {
    /// @inheritdoc ICircuitBreaker
    function isTripped(bytes32 key) public view virtual returns (bool) {
        return CircuitBreakerLib.isTripped(key);
    }

    /// @inheritdoc ICircuitBreaker
    function getThreshold(bytes32 key) public view virtual returns (uint256 threshold, uint48 windowSeconds) {
        return CircuitBreakerLib.getThreshold(key);
    }

    /// @inheritdoc ICircuitBreaker
    function getCumulative(bytes32 key) public view virtual returns (uint256 cumulative, uint48 windowStart) {
        return CircuitBreakerLib.getCumulative(key);
    }

    /// @inheritdoc ICircuitBreaker
    function setThreshold(bytes32 key, uint256 threshold, uint48 windowSeconds) public virtual {
        CircuitBreakerLib.setThreshold(key, threshold, windowSeconds);
    }

    /// @inheritdoc ICircuitBreaker
    function recordObservation(bytes32 key, uint256 value) public virtual {
        CircuitBreakerLib.recordObservation(key, value);
    }

    /// @inheritdoc ICircuitBreaker
    function reset(bytes32 key) public virtual {
        CircuitBreakerLib.reset(key);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect CircuitBreaker methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `getCumulative(bytes32)` 0x7e633690
    ///      `getThreshold(bytes32)` 0x42acf119
    ///      `isTripped(bytes32)` 0xcaac05fa
    ///      `recordObservation(bytes32,uint256)` 0xef13ca9d
    ///      `reset(bytes32)` 0xed3c7d40
    ///      `setThreshold(bytes32,uint256,uint48)` 0x802ec864
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"7e63369042acf119caac05faef13ca9ded3c7d40802ec864";
    }
}
