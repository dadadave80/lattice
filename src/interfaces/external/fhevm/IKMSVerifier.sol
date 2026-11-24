// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IKMSVerifier
/// @author Vendored minimal subset of Zama FHEVM (https://github.com/zama-ai/fhevm).
///         Upstream license: BSD-3-Clause-Clear.
/// @notice The call {FHEVMLib} makes on the FHEVM (Fully Homomorphic Encryption Virtual Machine) host's Key
///         Management Service (KMS) verifier, which checks public decryption proofs.
interface IKMSVerifier {
    /// @notice A proof signature recovers to an address that is not a registered KMS signer.
    error KMSInvalidSigner(address invalidSigner);

    /// @notice Verifies the KMS signatures in `decryptionProof` over `handlesList` and `decryptedResult`.
    /// @return Whether enough distinct registered signers signed; reverts on a malformed proof or an unknown signer.
    function verifyDecryptionEIP712KMSSignatures(
        bytes32[] memory handlesList,
        bytes memory decryptedResult,
        bytes memory decryptionProof
    ) external returns (bool);
}
