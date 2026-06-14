// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title LatticeVersion
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Canonical, library-wide version of the Lattice contract modules. This is the single
///         source of truth that every facet's lattice-version NatSpec tag mirrors.
/// @dev INTENTIONALLY SELECTOR-FREE. Lattice modules are EIP-2535 Diamond facets, and any
///      public/external VERSION() getter would register selector 0xffa1ad74, which would
///      collide the instant two facets are mounted in the same Diamond. These values are therefore
///      exposed only as internal constants (inlined at the call site, no public selector) and the
///      version itself MUST never be re-exposed as an external/public function on any facet.
///
///      Lattice is unaudited and pre-1.0; the semantic version starts at 0.1.0.
library LatticeVersion {
    /// @notice The full semantic version string of the Lattice library (e.g. "0.1.0").
    string internal constant VERSION = "0.1.0";

    /// @notice The major component of {VERSION}. Pre-1.0 / unaudited while this is 0.
    uint256 internal constant MAJOR = 0;

    /// @notice The minor component of {VERSION}.
    uint256 internal constant MINOR = 1;

    /// @notice The patch component of {VERSION}.
    uint256 internal constant PATCH = 0;
}
