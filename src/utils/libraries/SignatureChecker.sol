// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";

/// @title SignatureChecker
/// @notice Utility library for verifying signatures from both EOAs and ERC-1271 contracts.
/// @dev Implements the ERC-1271 magic value check with a safe `staticcall` fallback so
///      non-1271 contracts (or EOAs) never revert unexpectedly.
library SignatureChecker {
    /// @dev ERC-1271 magic value returned by valid contract signatures.
    bytes4 private constant ERC1271_MAGIC_VALUE = 0x1626ba7e;

    /// @notice Returns true if `signer` signed `hash` with `signature`.
    /// @dev If `signer` is an EOA: uses ECDSA recovery and checks address match.
    ///      If `signer` is a contract: tries ERC-1271 `isValidSignature`; falls back
    ///      to ECDSA if the contract call reverts (e.g. non-1271 contracts).
    /// @param signer The expected signer (EOA or contract).
    /// @param hash The signed data hash.
    /// @param signature The signature bytes.
    /// @return True if the signature is valid for the given signer and hash.
    function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature) internal view returns (bool) {
        // Try ECDSA recovery first
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
        if (err == ECDSA.RecoverError.NoError && recovered == signer) {
            return true;
        }

        // If signer is a contract, try ERC-1271
        if (signer.code.length > 0) {
            return isValidERC1271SignatureNow(signer, hash, signature);
        }

        return false;
    }

    /// @notice Returns true if the contract `signer` accepts `signature` for `hash` via ERC-1271.
    /// @dev Calls `signer.isValidSignature(hash, signature)` via staticcall and checks the
    ///      magic return value. Never reverts — returns false if the call fails.
    /// @param signer The contract that implements (or should implement) ERC-1271.
    /// @param hash The signed data hash.
    /// @param signature The signature bytes.
    /// @return True if the contract returns the ERC-1271 magic value.
    function isValidERC1271SignatureNow(address signer, bytes32 hash, bytes memory signature)
        internal
        view
        returns (bool)
    {
        // staticcall to isValidSignature(bytes32,bytes) selector = 0x1626ba7e
        (bool success, bytes memory result) =
            signer.staticcall(abi.encodeWithSelector(ERC1271_MAGIC_VALUE, hash, signature));
        return success && result.length >= 32 && abi.decode(result, (bytes4)) == ERC1271_MAGIC_VALUE;
    }
}
