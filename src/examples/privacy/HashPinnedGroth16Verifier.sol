// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IGroth16Verifier} from "@lattice/interfaces/privacy/IGroth16Verifier.sol";

/// @title HashPinnedGroth16Verifier
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Example guard in front of the generic {IGroth16Verifier}: callers still pass the verifying key
///         in calldata, so no key is stored on chain, but only the key whose `keccak256(abi.encode(vk))`
///         was fixed at deployment is accepted. Same ABI as the generic verifier, bound to one circuit.
/// @dev KEY PINNING, stored-hash pattern. The generic verifier checks a proof against whatever key it is
///      given, and whoever generates a key can know its trapdoor and forge a proof for any input. Checking
///      the key's hash against an immutable on every call leaves the caller no choice of key. Compute
///      {vkHash} off chain from the audited circuit's key in exactly the {IGroth16Verifier.VerifyingKey}
///      layout this contract receives (G2 pairs in `(c1, c0)` order). {PinnedWithdrawVerifier} shows the
///      constant pattern, for interfaces that do not carry the key.
///      EXAMPLE contract; not audited.
/// @custom:security-contact daveproxy80@gmail.com
contract HashPinnedGroth16Verifier is IGroth16Verifier {
    /// @notice The generic Groth16 verifier that a pinned key is forwarded to.
    IGroth16Verifier public immutable groth16;

    /// @notice `keccak256(abi.encode(vk))` of the only key this contract accepts.
    bytes32 public immutable vkHash;

    error HashPinnedGroth16Verifier__ZeroAddress();
    error HashPinnedGroth16Verifier__ZeroHash();

    /// @dev Thrown when the supplied key is not the pinned one.
    /// @param supplied `keccak256(abi.encode(vk))` of the key the caller passed.
    error HashPinnedGroth16Verifier__UnpinnedKey(bytes32 supplied);

    /// @param groth16_ A {Groth16Verifier} facet deployment, or a diamond that serves it.
    /// @param vkHash_ `keccak256(abi.encode(vk))` of the circuit's verifying key.
    constructor(IGroth16Verifier groth16_, bytes32 vkHash_) {
        if (address(groth16_) == address(0)) revert HashPinnedGroth16Verifier__ZeroAddress();
        if (vkHash_ == bytes32(0)) revert HashPinnedGroth16Verifier__ZeroHash();
        groth16 = groth16_;
        vkHash = vkHash_;
    }

    /// @inheritdoc IGroth16Verifier
    /// @dev Reverts with {HashPinnedGroth16Verifier__UnpinnedKey} unless `vk` hashes to {vkHash}.
    function verifyProof(VerifyingKey calldata vk, Proof calldata proof, uint256[] calldata input)
        external
        view
        returns (bool)
    {
        bytes32 supplied = keccak256(abi.encode(vk));
        if (supplied != vkHash) revert HashPinnedGroth16Verifier__UnpinnedKey(supplied);
        return groth16.verifyProof(vk, proof, input);
    }
}
