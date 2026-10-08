// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IGroth16Verifier} from "@lattice/interfaces/privacy/IGroth16Verifier.sol";
import {IShieldedWithdrawVerifier} from "@lattice/interfaces/privacy/IShieldedPool.sol";

/// @title PinnedWithdrawVerifier
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Example {IShieldedWithdrawVerifier} adapter: fits the generic {IGroth16Verifier} to a shielded
///         pool's 5-signal withdraw interface, with the circuit's verifying key compiled in. A consumer
///         subclasses it and returns their audited withdraw circuit's key from {_verifyingKey} as literals
///         (snarkjs `vkey.json`, G2 pairs swapped to `(c1, c0)`), then passes the subclass to `createPool`.
/// @dev KEY PINNING, constant pattern. The generic verifier checks a proof against whatever key it is given,
///      and whoever generates a key can know its trapdoor and forge a proof for any public signals. This
///      adapter never takes a key from its caller or from storage: the key lives in bytecode, so every
///      withdrawal from the pool is checked against one circuit. There is deliberately no setter; a new
///      circuit means a new adapter and a new pool. Point {groth16} at a verifier whose code cannot change
///      under the pool (a standalone facet deployment, or a diamond whose cut authority you already trust).
///      {HashPinnedGroth16Verifier} shows the stored-hash pattern for keys passed in calldata.
///      EXAMPLE contract; not audited.
/// @custom:security-contact daveproxy80@gmail.com
abstract contract PinnedWithdrawVerifier is IShieldedWithdrawVerifier {
    /// @notice The generic Groth16 verifier the pinned key is checked against.
    IGroth16Verifier public immutable groth16;

    error PinnedWithdrawVerifier__ZeroAddress();

    /// @param groth16_ A {Groth16Verifier} facet deployment, or a diamond that serves it.
    constructor(IGroth16Verifier groth16_) {
        if (address(groth16_) == address(0)) revert PinnedWithdrawVerifier__ZeroAddress();
        groth16 = groth16_;
    }

    /// @inheritdoc IShieldedWithdrawVerifier
    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[5] calldata input
    ) external view returns (bool) {
        uint256[] memory signals = new uint256[](5);
        for (uint256 i; i < 5; ++i) {
            signals[i] = input[i];
        }
        return groth16.verifyProof(_verifyingKey(), IGroth16Verifier.Proof({a: a, b: b, c: c}), signals);
    }

    /// @dev The pinned key, with `ic.length == 6`. MUST return compile-time constants: no storage reads, no
    ///      constructor arguments, no calls.
    function _verifyingKey() internal pure virtual returns (IGroth16Verifier.VerifyingKey memory vk);
}
