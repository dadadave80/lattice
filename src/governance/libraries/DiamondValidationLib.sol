// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title DiamondValidationLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Pure, Foundry-native pre-flight validation for composing ERC-7201 modules into one
///         EIP-2535 Diamond. Generalizes `StorageSlotVerificationTest`'s uniqueness check into a
///         reusable assertion: given a list of ERC-7201 namespaces, reverts on the first pair that
///         derives the same storage slot (a guaranteed storage collision).
/// @dev Utility-library pattern: no own storage, no facet, no ERC-165 registration; errors declared
///      here. Intended for deploy scripts and off-chain/on-chain pre-flight, NOT a hot path.
library DiamondValidationLib {
    /// @dev Thrown when two namespaces derive the same ERC-7201 storage slot.
    /// @param slot The colliding storage slot.
    /// @param first The first namespace that mapped to `slot`.
    /// @param second The second namespace that mapped to `slot`.
    error NamespaceCollision(bytes32 slot, string first, string second);

    /// @dev Thrown when a cut's `_init` reinitializer version would not advance past the Diamond's
    ///      current initialized version, so running it would re-execute an already-applied
    ///      initializer (e.g. replaying a v1 `initialize` after the Diamond is live).
    /// @param deployed The Diamond's current `getInitializedVersion()`.
    /// @param attempted The reinitializer version the pending cut's `_init` would use.
    error InitializerWouldReRun(uint64 deployed, uint64 attempted);

    /// @notice Derives the ERC-7201 storage slot for a namespace string.
    /// @dev `keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff))`.
    /// @param id The ERC-7201 namespace (e.g. "lattice.storage.Governor").
    /// @return The 32-byte storage slot.
    function erc7201Slot(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff));
    }

    /// @notice Reverts unless every namespace in `ids` derives a distinct ERC-7201 storage slot.
    /// @dev O(n^2) pairwise comparison — fine for the small module counts used at composition time.
    ///      An empty or single-element array trivially passes.
    /// @param ids The list of ERC-7201 namespaces to check for mutual disjointness.
    function assertNamespacesDisjoint(string[] memory ids) internal pure {
        uint256 n = ids.length;
        for (uint256 i; i < n; ++i) {
            bytes32 slotI = erc7201Slot(ids[i]);
            for (uint256 j = i + 1; j < n; ++j) {
                if (slotI == erc7201Slot(ids[j])) {
                    revert NamespaceCollision(slotI, ids[i], ids[j]);
                }
            }
        }
    }

    /// @notice Reverts unless a pending cut's `_init` reinitializer version strictly advances past
    ///         the Diamond's current initialized version.
    /// @dev Pre-flight guard an upgrade workflow runs before broadcasting a `diamondCut` that carries
    ///      an `_init`: the callback must use a reinitializer version strictly greater than the live
    ///      `getInitializedVersion()`, otherwise diamond-lib's `InitializableLib` would either reject
    ///      it on-chain (wasting a broadcast) or, if the same `initializer()` were re-runnable, reset
    ///      critical state. Mirrors the strictly-increasing rule enforced by `preReinitializer`.
    ///      Pure — reads no storage; the caller supplies `deployedVersion` from a prior
    ///      `getInitializedVersion()` read.
    /// @param deployedVersion The Diamond's current initialized version.
    /// @param cutInitVersion The reinitializer version the pending cut's `_init` would use.
    function assertReinitializerMonotonic(uint64 deployedVersion, uint64 cutInitVersion) internal pure {
        if (cutInitVersion <= deployedVersion) {
            revert InitializerWouldReRun(deployedVersion, cutInitVersion);
        }
    }
}
