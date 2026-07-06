// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IPlonkVerifier
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from snarkjs (https://github.com/iden3/snarkjs)
/// @notice External interface for a GENERIC PLONK proof verifier over BN254 (alt_bn128). Unlike a
///         snarkjs-generated verifier (which bakes one circuit's verifying key into bytecode), this
///         takes the verifying key as a parameter, so a single deployed facet verifies proofs for ANY
///         PLONK circuit. A reusable verifier primitive for the ZK privacy modules and consumers who
///         bring PLONK circuits.
/// @dev Verification follows the snarkjs (iden3) PLONK protocol (eprint 2019/953): Fiat-Shamir
///      challenges via a keccak256 transcript, Lagrange/vanishing evaluation at xi, then the batched
///      KZG pairing check `e(-A1, X_2) · e(B1, [1]_2) == 1`. Public inputs are range-checked
///      `< SNARK_SCALAR_FIELD` and proof coordinates `< BASE_FIELD`.
///
///      G2 ENCODING: the `X_2` coordinate pairs are given in PRECOMPILE order `(c1, c0)` — imaginary
///      first, then real. When building from a snarkjs `vkey.json`, swap each pair:
///      `x2[0] = [X_2[0][1], X_2[0][0]]`. G1 points use affine `(x, y)`; the point at infinity is `(0, 0)`.
interface IPlonkVerifier {
    /// @notice A PLONK proof over BN254 (snarkjs field order).
    struct Proof {
        uint256[2] a;
        uint256[2] b;
        uint256[2] c;
        uint256[2] z;
        uint256[2] t1;
        uint256[2] t2;
        uint256[2] t3;
        uint256[2] wxi;
        uint256[2] wxiw;
        uint256 eval_a;
        uint256 eval_b;
        uint256 eval_c;
        uint256 eval_s1;
        uint256 eval_s2;
        uint256 eval_zw;
    }

    /// @notice A PLONK verifying key over BN254.
    /// @dev `power` is the log2 of the domain size (`n = 2**power`); `omega` is the `n`-th root of unity
    ///      `Fr.w[power]`. `x2` is the SRS element `[x]_2` in `(c1, c0)` order.
    struct VerifyingKey {
        uint256[2] qm;
        uint256[2] ql;
        uint256[2] qr;
        uint256[2] qo;
        uint256[2] qc;
        uint256[2] s1;
        uint256[2] s2;
        uint256[2] s3;
        uint256 k1;
        uint256 k2;
        uint256 power;
        uint256 omega;
        uint256[2][2] x2;
    }

    /// @dev Thrown when the number of public inputs is zero or does not match the circuit.
    error PlonkInvalidInputs();

    /// @notice Verifies a PLONK proof against `vk` for the given public `input`.
    /// @dev Returns `false` (does not revert) for an invalid proof, an out-of-range public input
    ///      (`>= SNARK_SCALAR_FIELD`), an off-curve / out-of-range proof point, or a failed pairing.
    ///      Reverts only on structural misuse (empty input).
    /// @param vk The verifying key for the circuit.
    /// @param proof The PLONK proof.
    /// @param input The public inputs, in the circuit's public-signal order.
    /// @return True iff the proof is valid for `vk` and `input`.
    function verifyProof(VerifyingKey calldata vk, Proof calldata proof, uint256[] calldata input)
        external
        view
        returns (bool);
}
