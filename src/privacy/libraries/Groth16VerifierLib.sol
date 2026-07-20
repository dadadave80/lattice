// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IGroth16Verifier} from "@lattice/interfaces/privacy/IGroth16Verifier.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant GROTH16_VERIFIER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x6d832d8e is `type(IGroth16Verifier).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x6d832d8e), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IGROTH16VERIFIER_SLOT = 0x65fb5f0c2dd2a1b03fcdcf008584d060b7a7596bbc510b7022310e4dbd7682a9;

/// @title Groth16VerifierLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from snarkjs (https://github.com/iden3/snarkjs)
/// @notice Library implementing a generic Groth16 verifier over BN254 (alt_bn128): the verifying key is
///         a parameter, so one deployment verifies proofs for any circuit. Logic mirrors the audited
///         snarkjs verifier template (PR#36 hardening) but reads the key from calldata.
/// @dev Three-layer pattern: this library holds the logic; the stateless {Groth16Verifier} facet
///      forwards to it. The module is stateless — it only registers {IGroth16Verifier} for ERC-165.
library Groth16VerifierLib {
    /// @dev BN254 scalar field modulus `r` — public inputs must be `< R`.
    uint256 internal constant R = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    /// @dev BN254 base field modulus `q` — point coordinates must be `< Q`.
    uint256 internal constant Q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the Groth16Verifier module.
    /// @dev Must be called inside a pre/postInitializer block. Registers IGroth16Verifier for ERC-165.
    function __Groth16Verifier_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IGroth16Verifier interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IGROTH16VERIFIER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VERIFICATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Verifies a Groth16 proof. See {IGroth16Verifier.verifyProof}.
    /// @dev Returns false on any cryptographic invalidity / out-of-range value; reverts only on a
    ///      key/input arity mismatch.
    function verifyProof(
        IGroth16Verifier.VerifyingKey calldata vk,
        IGroth16Verifier.Proof calldata proof,
        uint256[] calldata input
    ) internal view returns (bool) {
        uint256 n = input.length;
        if (vk.ic.length != n + 1) revert IGroth16Verifier.Groth16InvalidVerifyingKey();

        // Public inputs must be canonical field elements (PR#36 hardening).
        for (uint256 i; i < n; ++i) {
            if (input[i] >= R) return false;
        }
        // Proof coordinates must be canonical base-field elements (a valid point has coords < Q).
        if (
            proof.a[0] >= Q || proof.a[1] >= Q || proof.c[0] >= Q || proof.c[1] >= Q || proof.b[0][0] >= Q
                || proof.b[0][1] >= Q || proof.b[1][0] >= Q || proof.b[1][1] >= Q
        ) {
            return false;
        }

        // vk_x = IC[0] + Σ input[i] · IC[i+1]
        (uint256 vx, uint256 vy) = (vk.ic[0][0], vk.ic[0][1]);
        for (uint256 i; i < n; ++i) {
            (uint256 mx, uint256 my, bool mulOk) = _ecMul(vk.ic[i + 1][0], vk.ic[i + 1][1], input[i]);
            if (!mulOk) return false;
            bool addOk;
            (vx, vy, addOk) = _ecAdd(vx, vy, mx, my);
            if (!addOk) return false;
        }

        // Pairing: e(-A, B) · e(alpha, beta) · e(vk_x, gamma) · e(C, delta) == 1
        uint256[24] memory buf;
        // -A (negate y): A.y < Q is guaranteed above, so (Q - A.y) % Q is safe (0 stays 0).
        buf[0] = proof.a[0];
        buf[1] = proof.a[1] == 0 ? 0 : Q - proof.a[1];
        // B
        buf[2] = proof.b[0][0];
        buf[3] = proof.b[0][1];
        buf[4] = proof.b[1][0];
        buf[5] = proof.b[1][1];
        // alpha, beta
        buf[6] = vk.alpha[0];
        buf[7] = vk.alpha[1];
        buf[8] = vk.beta[0][0];
        buf[9] = vk.beta[0][1];
        buf[10] = vk.beta[1][0];
        buf[11] = vk.beta[1][1];
        // vk_x, gamma
        buf[12] = vx;
        buf[13] = vy;
        buf[14] = vk.gamma[0][0];
        buf[15] = vk.gamma[0][1];
        buf[16] = vk.gamma[1][0];
        buf[17] = vk.gamma[1][1];
        // C, delta
        buf[18] = proof.c[0];
        buf[19] = proof.c[1];
        buf[20] = vk.delta[0][0];
        buf[21] = vk.delta[0][1];
        buf[22] = vk.delta[1][0];
        buf[23] = vk.delta[1][1];

        return _pairing(buf);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          BN254 PRECOMPILE HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev G1 scalar multiplication via the ecMul precompile (0x07): `(x, y) · s`.
    function _ecMul(uint256 x, uint256 y, uint256 s) private view returns (uint256 rx, uint256 ry, bool ok) {
        uint256[3] memory inp = [x, y, s];
        uint256[2] memory out;
        assembly ("memory-safe") {
            ok := staticcall(gas(), 0x07, inp, 0x60, out, 0x40)
        }
        return (out[0], out[1], ok);
    }

    /// @dev G1 point addition via the ecAdd precompile (0x06): `(x1, y1) + (x2, y2)`.
    function _ecAdd(uint256 x1, uint256 y1, uint256 x2, uint256 y2)
        private
        view
        returns (uint256 rx, uint256 ry, bool ok)
    {
        uint256[4] memory inp = [x1, y1, x2, y2];
        uint256[2] memory out;
        assembly ("memory-safe") {
            ok := staticcall(gas(), 0x06, inp, 0x80, out, 0x40)
        }
        return (out[0], out[1], ok);
    }

    /// @dev BN254 pairing check via the ecPairing precompile (0x08) over 4 pairs (768 bytes).
    /// @return True iff the staticcall succeeds and the pairing product is 1.
    function _pairing(uint256[24] memory buf) private view returns (bool) {
        uint256[1] memory out;
        bool ok;
        assembly ("memory-safe") {
            ok := staticcall(gas(), 0x08, buf, 768, out, 0x20)
        }
        return ok && out[0] == 1;
    }
}
