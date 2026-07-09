// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IGroth16Verifier
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from snarkjs (https://github.com/iden3/snarkjs)
/// @notice External interface for a GENERIC Groth16 proof verifier over BN254 (alt_bn128). Unlike a
///         snarkjs-generated verifier (which bakes one circuit's verifying key into bytecode), this
///         takes the verifying key as a parameter, so a single deployed facet verifies proofs for ANY
///         Groth16 circuit. The building block the ZK privacy modules (shielded transfers, membership,
///         voting) plug their circuit's key into.
/// @dev Verification is the standard Groth16 pairing check
///      `e(-A, B) · e(alpha, beta) · e(vk_x, gamma) · e(C, delta) == 1`, where
///      `vk_x = IC[0] + Σ input[i]·IC[i+1]`, evaluated with the BN254 precompiles (0x06/0x07/0x08).
///      Public inputs are range-checked `< SNARK_SCALAR_FIELD` and proof coordinates `< BASE_FIELD`
///      (snarkjs PR#36 hardening) before the pairing.
///
///      G2 ENCODING: every G2 coordinate pair is given in PRECOMPILE order `(c1, c0)` — imaginary part
///      first, then real — matching `snarkjs zkey export soliditycalldata` output for the proof's `b`
///      and the EIP-197 pairing input. When building a {VerifyingKey} from a snarkjs `vkey.json`, swap
///      each G2 pair: e.g. `beta.x = [vk_beta_2[0][1], vk_beta_2[0][0]]`.
interface IGroth16Verifier {
    /// @notice A Groth16 proof over BN254.
    /// @param a The G1 point A `(x, y)`.
    /// @param b The G2 point B, each coordinate pair in `(c1, c0)` precompile order.
    /// @param c The G1 point C `(x, y)`.
    struct Proof {
        uint256[2] a;
        uint256[2][2] b;
        uint256[2] c;
    }

    /// @notice A Groth16 verifying key over BN254.
    /// @param alpha The G1 point `alpha_1`.
    /// @param beta The G2 point `beta_2`, in `(c1, c0)` order.
    /// @param gamma The G2 point `gamma_2`, in `(c1, c0)` order.
    /// @param delta The G2 point `delta_2`, in `(c1, c0)` order.
    /// @param ic The IC G1 points; length MUST equal `publicInputs + 1`.
    struct VerifyingKey {
        uint256[2] alpha;
        uint256[2][2] beta;
        uint256[2][2] gamma;
        uint256[2][2] delta;
        uint256[2][] ic;
    }

    /// @dev Thrown when `vk.ic.length != input.length + 1` (the key does not match the input arity).
    error Groth16InvalidVerifyingKey();

    /// @notice Verifies a Groth16 proof against `vk` for the given public `input`.
    /// @dev Returns `false` (does not revert) for an invalid proof, an out-of-range public input
    ///      (`>= SNARK_SCALAR_FIELD`), an off-curve / out-of-range proof point, or a failed pairing.
    ///      Reverts only on structural misuse (key/input arity mismatch).
    /// @param vk The verifying key for the circuit.
    /// @param proof The Groth16 proof.
    /// @param input The public inputs, in the circuit's public-signal order.
    /// @return True iff the proof is valid for `vk` and `input`.
    function verifyProof(VerifyingKey calldata vk, Proof calldata proof, uint256[] calldata input)
        external
        view
        returns (bool);
}
