// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IPlonkVerifier} from "@lattice/interfaces/privacy/IPlonkVerifier.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant PLONK_VERIFIER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x5d484314 is `type(IPlonkVerifier).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x5d484314), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IPLONKVERIFIER_SLOT = 0xb1e78a1a6e11f30e01de857f602d74246da41ae3318d8e6afc2b73cc1cbe0ede;

/// @title PlonkVerifierLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing a generic PLONK verifier over BN254 (alt_bn128): the verifying key is a
///         parameter, so one deployment verifies proofs for any circuit. Faithful port of the snarkjs
///         (iden3) PLONK verifier (eprint 2019/953) — keccak256 Fiat-Shamir transcript, Lagrange
///         evaluation at xi, and the batched KZG pairing check.
/// @dev Three-layer pattern: this library holds the logic; the stateless {PlonkVerifier} facet forwards
///      to it. Stateless — it only registers {IPlonkVerifier} for ERC-165.
library PlonkVerifierLib {
    /// @dev BN254 scalar field modulus `r`.
    uint256 internal constant Q = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    /// @dev BN254 base field modulus `q` — point coordinates must be `< QF`.
    uint256 internal constant QF = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    // BN254 G2 generator `[1]_2` in precompile order (c1, c0).
    uint256 internal constant G2_X1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 internal constant G2_X0 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 internal constant G2_Y1 = 4082367875863433681332203403145435568316851327593401208105741076214120093531;
    uint256 internal constant G2_Y0 = 8495653923123431417604973247489272438418190587263600148770280649306958101930;

    /// @dev Scratch space for challenges and derived scalars (memory to avoid stack-too-deep).
    struct St {
        uint256 beta;
        uint256 gamma;
        uint256 alpha;
        uint256 xi;
        uint256 v1;
        uint256 v2;
        uint256 v3;
        uint256 v4;
        uint256 v5;
        uint256 u;
        uint256 xin;
        uint256 zh;
        uint256 l1;
        uint256 pi;
        uint256 r0;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the PlonkVerifier module.
    /// @dev Must be called inside a pre/postInitializer block. Registers IPlonkVerifier for ERC-165.
    function __PlonkVerifier_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    /// @notice Registers support for the IPlonkVerifier interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IPLONKVERIFIER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VERIFICATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Verifies a PLONK proof. See {IPlonkVerifier.verifyProof}.
    function verifyProof(
        IPlonkVerifier.VerifyingKey calldata vk,
        IPlonkVerifier.Proof calldata proof,
        uint256[] calldata input
    ) internal view returns (bool) {
        if (input.length == 0) revert IPlonkVerifier.PlonkInvalidInputs();

        // Verifying key must be well-formed: a real domain (power within the BN254 2-adicity, 28, so
        // `1 << power` cannot overflow) and on-curve selector/permutation commitments. A malformed key
        // returns false rather than reverting inside a precompile (matches the proof-point path).
        if (vk.power == 0 || vk.power > 28) return false;
        if (!_vkWellFormed(vk)) return false;

        // Public inputs must be canonical field elements.
        for (uint256 i; i < input.length; ++i) {
            if (input[i] >= Q) return false;
        }
        // All proof commitments must be valid curve points (snarkjs isWellConstructed).
        if (!_wellConstructed(proof)) return false;
        // Proof evaluations must be canonical field elements (snarkjs checkInput): they enter the
        // Fiat-Shamir transcript raw, so this keeps the transcript byte-identical to snarkjs.
        if (
            proof.eval_a >= Q || proof.eval_b >= Q || proof.eval_c >= Q || proof.eval_s1 >= Q || proof.eval_s2 >= Q
                || proof.eval_zw >= Q
        ) return false;

        St memory st;
        _challenges(st, vk, proof, input);
        _evaluations(st, vk, proof, input);

        uint256[2] memory d = _calcD(st, vk, proof);
        uint256[2] memory f = _calcF(st, vk, proof, d);
        uint256[2] memory e = _calcE(st, proof);
        return _validPairing(st, vk, proof, e, f);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          FIAT-SHAMIR CHALLENGES
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev beta = H(Qm,Ql,Qr,Qo,Qc,S1,S2,S3, input..., A,B,C). Chunked to stay within the stack limit.
    function _beta(
        IPlonkVerifier.VerifyingKey calldata vk,
        IPlonkVerifier.Proof calldata proof,
        uint256[] calldata input
    ) private pure returns (uint256) {
        bytes memory tq = abi.encodePacked(
            vk.qm[0], vk.qm[1], vk.ql[0], vk.ql[1], vk.qr[0], vk.qr[1], vk.qo[0], vk.qo[1], vk.qc[0], vk.qc[1]
        );
        bytes memory ts = abi.encodePacked(vk.s1[0], vk.s1[1], vk.s2[0], vk.s2[1], vk.s3[0], vk.s3[1]);
        bytes memory tp = abi.encodePacked(proof.a[0], proof.a[1], proof.b[0], proof.b[1], proof.c[0], proof.c[1]);
        return uint256(keccak256(bytes.concat(tq, ts, abi.encodePacked(input), tp))) % Q;
    }

    function _challenges(
        St memory st,
        IPlonkVerifier.VerifyingKey calldata vk,
        IPlonkVerifier.Proof calldata proof,
        uint256[] calldata input
    ) private pure {
        st.beta = _beta(vk, proof, input);
        // gamma = H(beta)
        st.gamma = uint256(keccak256(abi.encodePacked(st.beta))) % Q;
        // alpha = H(beta, gamma, Z)
        st.alpha = uint256(keccak256(abi.encodePacked(st.beta, st.gamma, proof.z[0], proof.z[1]))) % Q;
        // xi = H(alpha, T1, T2, T3)
        st.xi = uint256(
            keccak256(
                abi.encodePacked(st.alpha, proof.t1[0], proof.t1[1], proof.t2[0], proof.t2[1], proof.t3[0], proof.t3[1])
            )
        ) % Q;
        // v1 = H(xi, eval_a, eval_b, eval_c, eval_s1, eval_s2, eval_zw); v2..v5 = powers
        st.v1 = uint256(
            keccak256(
                abi.encodePacked(
                    st.xi, proof.eval_a, proof.eval_b, proof.eval_c, proof.eval_s1, proof.eval_s2, proof.eval_zw
                )
            )
        ) % Q;
        st.v2 = mulmod(st.v1, st.v1, Q);
        st.v3 = mulmod(st.v2, st.v1, Q);
        st.v4 = mulmod(st.v3, st.v1, Q);
        st.v5 = mulmod(st.v4, st.v1, Q);
        // u = H(Wxi, Wxiw)
        st.u = uint256(keccak256(abi.encodePacked(proof.wxi[0], proof.wxi[1], proof.wxiw[0], proof.wxiw[1]))) % Q;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       LAGRANGE / PI / R0 (scalars)
    //////////////////////////////////////////////////////////////////////////*//

    function _evaluations(
        St memory st,
        IPlonkVerifier.VerifyingKey calldata vk,
        IPlonkVerifier.Proof calldata proof,
        uint256[] calldata input
    ) private view {
        // xin = xi^(2^power); zh = xin - 1
        uint256 xin = st.xi;
        for (uint256 i; i < vk.power; ++i) {
            xin = mulmod(xin, xin, Q);
        }
        st.xin = xin;
        st.zh = addmod(xin, Q - 1, Q);
        _lagrange(st, vk, input);
        st.r0 = _calcR0(st, proof);
    }

    /// @dev L[i] = (wᵢ·zh) / (n·(ξ - wᵢ)), w₁=1, wᵢ₊₁=wᵢ·ω; accumulates PI = -Σ inputᵢ·L[i+1] into st.
    function _lagrange(St memory st, IPlonkVerifier.VerifyingKey calldata vk, uint256[] calldata input) private view {
        uint256 n = 1 << vk.power;
        uint256 w = 1;
        for (uint256 i = 1; i <= input.length; ++i) {
            uint256 li = mulmod(mulmod(w, st.zh, Q), _inv(mulmod(n, addmod(st.xi, Q - w, Q), Q)), Q);
            if (i == 1) st.l1 = li;
            st.pi = addmod(st.pi, Q - mulmod(input[i - 1], li, Q), Q);
            w = mulmod(w, vk.omega, Q);
        }
    }

    /// @dev r0 = pi - l1·α² - α·eval_zw·(a+β·s1+γ)(b+β·s2+γ)(c+γ).
    function _calcR0(St memory st, IPlonkVerifier.Proof calldata proof) private pure returns (uint256) {
        uint256 e2 = mulmod(st.l1, mulmod(st.alpha, st.alpha, Q), Q);
        uint256 e3 = mulmod(
            mulmod(
                addmod(addmod(proof.eval_a, mulmod(st.beta, proof.eval_s1, Q), Q), st.gamma, Q),
                addmod(addmod(proof.eval_b, mulmod(st.beta, proof.eval_s2, Q), Q), st.gamma, Q),
                Q
            ),
            addmod(proof.eval_c, st.gamma, Q),
            Q
        );
        e3 = mulmod(mulmod(e3, proof.eval_zw, Q), st.alpha, Q);
        return addmod(addmod(st.pi, Q - e2, Q), Q - e3, Q);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          D / F / E (G1 points)
    //////////////////////////////////////////////////////////////////////////*//

    function _calcD(St memory st, IPlonkVerifier.VerifyingKey calldata vk, IPlonkVerifier.Proof calldata proof)
        private
        view
        returns (uint256[2] memory d)
    {
        // d1 = Qm*(a*b) + Ql*a + Qr*b + Qo*c + Qc
        d = _mul(_cm(vk.qm), mulmod(proof.eval_a, proof.eval_b, Q));
        d = _add(d, _mul(_cm(vk.ql), proof.eval_a));
        d = _add(d, _mul(_cm(vk.qr), proof.eval_b));
        d = _add(d, _mul(_cm(vk.qo), proof.eval_c));
        d = _add(d, _cm(vk.qc));
        // d2 = Z * ( (a+βξ+γ)(b+βξk1+γ)(c+βξk2+γ)·α + l1·α² + u )
        d = _add(d, _mul(_cm(proof.z), _d2Coeff(st, vk, proof)));
        // d3 = S3 * ( (a+β·s1+γ)(b+β·s2+γ)·α·β·zw )
        d = _sub(d, _mul(_cm(vk.s3), _d3Coeff(st, proof)));
        // d4 = (T1 + T2·ξⁿ + T3·ξ²ⁿ) · zh
        uint256[2] memory d4 = _mul(_cm(proof.t3), mulmod(st.xin, st.xin, Q));
        d4 = _add(d4, _mul(_cm(proof.t2), st.xin));
        d4 = _add(d4, _cm(proof.t1));
        d = _sub(d, _mul(d4, st.zh));
    }

    function _d2Coeff(St memory st, IPlonkVerifier.VerifyingKey calldata vk, IPlonkVerifier.Proof calldata proof)
        private
        pure
        returns (uint256)
    {
        uint256 betaxi = mulmod(st.beta, st.xi, Q);
        uint256 a = mulmod(
            mulmod(
                addmod(addmod(proof.eval_a, betaxi, Q), st.gamma, Q),
                addmod(addmod(proof.eval_b, mulmod(betaxi, vk.k1, Q), Q), st.gamma, Q),
                Q
            ),
            addmod(addmod(proof.eval_c, mulmod(betaxi, vk.k2, Q), Q), st.gamma, Q),
            Q
        );
        a = mulmod(a, st.alpha, Q);
        a = addmod(a, mulmod(st.l1, mulmod(st.alpha, st.alpha, Q), Q), Q);
        return addmod(a, st.u, Q);
    }

    function _d3Coeff(St memory st, IPlonkVerifier.Proof calldata proof) private pure returns (uint256) {
        uint256 a = mulmod(
            addmod(addmod(proof.eval_a, mulmod(st.beta, proof.eval_s1, Q), Q), st.gamma, Q),
            addmod(addmod(proof.eval_b, mulmod(st.beta, proof.eval_s2, Q), Q), st.gamma, Q),
            Q
        );
        return mulmod(a, mulmod(mulmod(st.alpha, st.beta, Q), proof.eval_zw, Q), Q);
    }

    function _calcF(
        St memory st,
        IPlonkVerifier.VerifyingKey calldata vk,
        IPlonkVerifier.Proof calldata proof,
        uint256[2] memory d
    ) private view returns (uint256[2] memory f) {
        f = _add(d, _mul(_cm(proof.a), st.v1));
        f = _add(f, _mul(_cm(proof.b), st.v2));
        f = _add(f, _mul(_cm(proof.c), st.v3));
        f = _add(f, _mul(_cm(vk.s1), st.v4));
        f = _add(f, _mul(_cm(vk.s2), st.v5));
    }

    function _calcE(St memory st, IPlonkVerifier.Proof calldata proof) private view returns (uint256[2] memory) {
        // e = -r0 + v1·a + v2·b + v3·c + v4·s1 + v5·s2 + u·zw
        uint256 e = addmod(Q - st.r0, mulmod(st.v1, proof.eval_a, Q), Q);
        e = addmod(e, mulmod(st.v2, proof.eval_b, Q), Q);
        e = addmod(e, mulmod(st.v3, proof.eval_c, Q), Q);
        e = addmod(e, mulmod(st.v4, proof.eval_s1, Q), Q);
        e = addmod(e, mulmod(st.v5, proof.eval_s2, Q), Q);
        e = addmod(e, mulmod(st.u, proof.eval_zw, Q), Q);
        uint256[2] memory g1 = [uint256(1), uint256(2)];
        return _mul(g1, e);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              PAIRING
    //////////////////////////////////////////////////////////////////////////*//

    function _validPairing(
        St memory st,
        IPlonkVerifier.VerifyingKey calldata vk,
        IPlonkVerifier.Proof calldata proof,
        uint256[2] memory e,
        uint256[2] memory f
    ) private view returns (bool) {
        // A1 = Wxi + u·Wxiw
        uint256[2] memory a1 = _mul(_cm(proof.wxiw), st.u);
        a1 = _add(a1, _cm(proof.wxi));
        return _pairCheck(_neg(a1), vk.x2, _calcB1(st, vk, proof, e, f));
    }

    /// @dev B1 = ξ·Wxi + (u·ξ·ω)·Wxiw + F - E.
    function _calcB1(
        St memory st,
        IPlonkVerifier.VerifyingKey calldata vk,
        IPlonkVerifier.Proof calldata proof,
        uint256[2] memory e,
        uint256[2] memory f
    ) private view returns (uint256[2] memory b1) {
        uint256 s = mulmod(mulmod(st.u, st.xi, Q), vk.omega, Q);
        b1 = _mul(_cm(proof.wxi), st.xi);
        b1 = _add(b1, _mul(_cm(proof.wxiw), s));
        b1 = _add(b1, f);
        b1 = _sub(b1, e);
    }

    /// @dev e(-A1, X_2) · e(B1, [1]_2) == 1 via the pairing precompile (0x08).
    function _pairCheck(uint256[2] memory a1neg, uint256[2][2] calldata x2, uint256[2] memory b1)
        private
        view
        returns (bool)
    {
        uint256[12] memory buf;
        buf[0] = a1neg[0];
        buf[1] = a1neg[1];
        buf[2] = x2[0][0];
        buf[3] = x2[0][1];
        buf[4] = x2[1][0];
        buf[5] = x2[1][1];
        buf[6] = b1[0];
        buf[7] = b1[1];
        buf[8] = G2_X1;
        buf[9] = G2_X0;
        buf[10] = G2_Y1;
        buf[11] = G2_Y0;
        uint256[1] memory out;
        bool ok;
        assembly ("memory-safe") {
            ok := staticcall(gas(), 0x08, buf, 384, out, 0x20)
        }
        return ok && out[0] == 1;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          BN254 / FIELD HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Checks every proof commitment is a valid BN254 G1 point (on-curve or the infinity (0,0)).
    function _wellConstructed(IPlonkVerifier.Proof calldata p) private pure returns (bool) {
        return _onCurve(p.a) && _onCurve(p.b) && _onCurve(p.c) && _onCurve(p.z) && _onCurve(p.t1) && _onCurve(p.t2)
            && _onCurve(p.t3) && _onCurve(p.wxi) && _onCurve(p.wxiw);
    }

    /// @dev Checks every verifying-key G1 commitment is a valid BN254 point. The G2 point `x2` is
    ///      validated implicitly by the pairing precompile (a bad `x2` makes the pairing return false).
    function _vkWellFormed(IPlonkVerifier.VerifyingKey calldata vk) private pure returns (bool) {
        return _onCurve(vk.qm) && _onCurve(vk.ql) && _onCurve(vk.qr) && _onCurve(vk.qo) && _onCurve(vk.qc)
            && _onCurve(vk.s1) && _onCurve(vk.s2) && _onCurve(vk.s3);
    }

    /// @dev BN254 G1 on-curve test: y² == x³ + 3 (mod QF), with (0,0) the valid point at infinity.
    function _onCurve(uint256[2] calldata pt) private pure returns (bool) {
        uint256 x = pt[0];
        uint256 y = pt[1];
        if (x >= QF || y >= QF) return false;
        if (x == 0 && y == 0) return true;
        uint256 lhs = mulmod(y, y, QF);
        uint256 rhs = addmod(mulmod(mulmod(x, x, QF), x, QF), 3, QF);
        return lhs == rhs;
    }

    /// @dev Copies a calldata G1 point into memory (Solidity overloads ignore data location).
    function _cm(uint256[2] calldata p) private pure returns (uint256[2] memory r) {
        r[0] = p[0];
        r[1] = p[1];
    }

    /// @dev G1 scalar multiplication via the ecMul precompile (0x07). Reverts on precompile failure.
    function _mul(uint256[2] memory p, uint256 s) private view returns (uint256[2] memory r) {
        uint256[3] memory inp = [p[0], p[1], s];
        bool ok;
        assembly ("memory-safe") {
            ok := staticcall(gas(), 0x07, inp, 0x60, r, 0x40)
        }
        require(ok, "ecMul");
    }

    /// @dev G1 point addition via the ecAdd precompile (0x06). Reverts on precompile failure.
    function _add(uint256[2] memory p1, uint256[2] memory p2) private view returns (uint256[2] memory r) {
        uint256[4] memory inp = [p1[0], p1[1], p2[0], p2[1]];
        bool ok;
        assembly ("memory-safe") {
            ok := staticcall(gas(), 0x06, inp, 0x80, r, 0x40)
        }
        require(ok, "ecAdd");
    }

    /// @dev G1 subtraction: p1 - p2 = p1 + (-p2).
    function _sub(uint256[2] memory p1, uint256[2] memory p2) private view returns (uint256[2] memory) {
        return _add(p1, _neg(p2));
    }

    /// @dev G1 negation: (x, QF - y), with (x, 0) mapping to itself.
    function _neg(uint256[2] memory p) private pure returns (uint256[2] memory) {
        if (p[0] == 0 && p[1] == 0) return p;
        return [p[0], QF - p[1]];
    }

    /// @dev Modular inverse mod Q via Fermat (a^(Q-2)) using the modexp precompile (0x05).
    function _inv(uint256 a) private view returns (uint256 r) {
        uint256 q = Q;
        assembly ("memory-safe") {
            let p := mload(0x40)
            mstore(p, 0x20)
            mstore(add(p, 0x20), 0x20)
            mstore(add(p, 0x40), 0x20)
            mstore(add(p, 0x60), a)
            mstore(add(p, 0x80), sub(q, 2))
            mstore(add(p, 0xa0), q)
            if iszero(staticcall(gas(), 0x05, p, 0xc0, p, 0x20)) { revert(0, 0) }
            r := mload(p)
        }
    }
}
