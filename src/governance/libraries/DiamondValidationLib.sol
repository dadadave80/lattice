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
}
