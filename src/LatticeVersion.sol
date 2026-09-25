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
///
///      DO NOT bump these values by hand: Release Please rewrites the annotated lines on every
///      release PR (this file is an `extra-files` generic-updater target in
///      release-please-config.json), and {DeployRelease} defaults to {VERSION} — so the released
///      registry keys, this library, and the git tag stay in lockstep with zero manual edits.
library LatticeVersion {
    /// @notice The full semantic version string of the Lattice library (e.g. "0.1.0").
    string internal constant VERSION = "0.4.0"; // x-release-please-version

    /// @notice The major component of {VERSION}. Pre-1.0 / unaudited while this is 0.
    /// @dev The component constants use the digit-free `uint` alias ON PURPOSE: release-please's
    /// generic updater rewrites numbers on its annotated lines (the trailing markers below), and the
    /// `256` in `uint256` got clobbered to the non-type `uint0` in the 0.2.0 release PR. Keep those
    /// lines free of any digits except the version value itself; the forgefmt disable comments stop
    /// `forge fmt` from normalizing `uint` back to `uint256`.
    // forgefmt: disable-next-item
    uint internal constant MAJOR = 0; // x-release-please-major

    /// @notice The minor component of {VERSION}.
    // forgefmt: disable-next-item
    uint internal constant MINOR = 4; // x-release-please-minor

    /// @notice The patch component of {VERSION}.
    // forgefmt: disable-next-item
    uint internal constant PATCH = 0; // x-release-please-patch
}
