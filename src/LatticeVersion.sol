// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title LatticeVersion
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Canonical library-wide release version, used by registry keys and release manifests.
///         Module composition tags describe code facts; they deliberately carry no duplicate version.
/// @dev INTENTIONALLY SELECTOR-FREE. Lattice modules are EIP-2535 Diamond facets, and any
///      public/external VERSION() getter would register selector 0xffa1ad74, which would
///      collide the instant two facets are mounted in the same Diamond. These values are therefore
///      exposed as internal constants, with no generic VERSION() facet selector. ERC-3643's required
///      `version()` method is an explicit exception in its closed profile. Version changes affect its
///      runtime and require regenerating that profile's build-bound fingerprints.
///
///      Lattice is unaudited and pre-1.0; the semantic version starts at 0.1.0.
///
///      Release Please chooses the next version and rewrites these annotated lines (`extra-files`
///      in release-please-config.json). Import its generated version change into reviewed source
///      preparation, regenerate affected profiles, then freeze release inputs before tagging.
///      {DeployRelease} defaults to {VERSION}; see REGISTRY_DEPLOYMENTS.md for that release sequence.
library LatticeVersion {
    /// @notice The full semantic version string of the Lattice library (e.g. "0.1.0").
    string internal constant VERSION = "0.5.0"; // x-release-please-version

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
    uint internal constant MINOR = 5; // x-release-please-minor

    /// @notice The patch component of {VERSION}.
    // forgefmt: disable-next-item
    uint internal constant PATCH = 0; // x-release-please-patch
}
