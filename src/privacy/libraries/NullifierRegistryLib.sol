// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title NullifierRegistryLib
/// @author David Dada
/// @notice Append-only spent-set for double-spend protection in nullifier-based privacy
///         schemes (shielded transfers, anonymous voting). A nullifier is a one-time tag
///         a ZK circuit derives from a secret; spending it once and reverting on reuse is
///         what prevents replay / double-spend without revealing which note was consumed.
/// @dev Stateless helper — no own ERC-7201 slot; `Registry` is held inline in the
///      consumer's namespaced storage (same pattern as {EnumerableSet}). Always
///      {spend} a nullifier BEFORE any external interaction (strict CEI) so a reentrant
///      call cannot replay it.
///
///      A nullifier is a BN254 field element, so {spend} enforces canonicality
///      (`0 < nullifier < SNARK_SCALAR_FIELD`). This closes the non-canonical-field-element
///      double-spend: an EC scalar mult is inherently mod-p, so `n` and `n + p` are the
///      SAME circuit-level nullifier even though they are distinct uint256 keys — accepting
///      a non-reduced value would let one witness be spent more than once. Mirrors the
///      `< SNARK_SCALAR_FIELD` leaf invariant of {IncrementalMerkleTreeLib}/LeanIMT.
library NullifierRegistryLib {
    /// @dev BN254 / alt_bn128 scalar field modulus (the public SNARK field constant).
    uint256 internal constant SNARK_SCALAR_FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    struct Registry {
        mapping(uint256 nullifier => bool spent) _spent;
    }

    /// @dev Thrown when spending a nullifier that was already spent.
    /// @param nullifier The already-spent nullifier.
    error NullifierAlreadySpent(uint256 nullifier);

    /// @dev Thrown when spending the zero nullifier (rejected as a reserved sentinel).
    error NullifierIsZero();

    /// @dev Thrown when spending a non-canonical nullifier (>= the SNARK scalar field).
    /// @param nullifier The out-of-field nullifier.
    error NullifierOutOfField(uint256 nullifier);

    /// @notice Returns whether `nullifier` has been spent.
    /// @param self The registry storage reference.
    /// @param nullifier The nullifier to query.
    function isSpent(Registry storage self, uint256 nullifier) internal view returns (bool) {
        return self._spent[nullifier];
    }

    /// @notice Marks `nullifier` spent, reverting if it is zero, out of field, or already spent.
    /// @dev Call BEFORE any external interaction (CEI) to block reentrant replay. Pass only the
    ///      canonical field element the verifier validated as a public input, never raw calldata.
    /// @param self The registry storage reference.
    /// @param nullifier The nullifier to consume.
    function spend(Registry storage self, uint256 nullifier) internal {
        if (nullifier == 0) revert NullifierIsZero();
        if (nullifier >= SNARK_SCALAR_FIELD) revert NullifierOutOfField(nullifier);
        if (self._spent[nullifier]) revert NullifierAlreadySpent(nullifier);
        self._spent[nullifier] = true;
    }
}
