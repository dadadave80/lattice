// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ECDSA
/// @notice Elliptic Curve Digital Signature Algorithm (ECDSA) operations.
/// @dev Utility library for verifying and recovering signers from compact signatures.
///      High-S signatures are rejected to prevent signature malleability.
///      Based on OpenZeppelin v5 and Solady patterns.
library ECDSA {
    enum RecoverError {
        NoError,
        InvalidSignature,
        InvalidSignatureLength,
        InvalidSignatureS
    }

    error ECDSAInvalidSignature();
    error ECDSAInvalidSignatureLength(uint256 length);
    error ECDSAInvalidSignatureS(bytes32 s);

    /// @notice Returns the address that signed a hashed message with `signature`.
    /// @dev Reverts with the appropriate error for invalid signatures.
    /// @param hash The hash of the signed message.
    /// @param signature The signature bytes (65 bytes).
    /// @return signer The recovered signer address.
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address signer) {
        (address recovered, RecoverError err, bytes32 errArg) = tryRecover(hash, signature);
        _throwError(err, errArg);
        return recovered;
    }

    /// @notice Returns the address that signed a hashed message with compact (r, vs) signature.
    /// @dev EIP-2098 compact signature format.
    /// @param hash The hash of the signed message.
    /// @param r The r component of the signature.
    /// @param vs The combined v and s component (yParity bit in high bit of vs).
    /// @return signer The recovered signer address.
    function recover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address signer) {
        (address recovered, RecoverError err, bytes32 errArg) = tryRecover(hash, r, vs);
        _throwError(err, errArg);
        return recovered;
    }

    /// @notice Returns the address that signed a hashed message with (v, r, s) components.
    /// @param hash The hash of the signed message.
    /// @param v The recovery byte (27 or 28).
    /// @param r The r component of the signature.
    /// @param s The s component of the signature.
    /// @return signer The recovered signer address.
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address signer) {
        (address recovered, RecoverError err, bytes32 errArg) = tryRecover(hash, v, r, s);
        _throwError(err, errArg);
        return recovered;
    }

    /// @notice Attempts to recover the signer from a full signature, returning an error enum instead of reverting.
    /// @param hash The hash of the signed message.
    /// @param signature The signature bytes.
    /// @return recovered The recovered signer (address(0) on error).
    /// @return err The error enum value.
    /// @return errArg Additional error argument (s value for InvalidSignatureS, length for InvalidSignatureLength).
    function tryRecover(bytes32 hash, bytes memory signature)
        internal
        pure
        returns (address recovered, RecoverError err, bytes32 errArg)
    {
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly ("memory-safe") {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            return tryRecover(hash, v, r, s);
        } else if (signature.length == 64) {
            bytes32 r;
            bytes32 vs;
            assembly ("memory-safe") {
                r := mload(add(signature, 0x20))
                vs := mload(add(signature, 0x40))
            }
            return tryRecover(hash, r, vs);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength, bytes32(signature.length));
        }
    }

    /// @notice Attempts to recover the signer from an EIP-2098 compact (r, vs) signature.
    /// @param hash The hash of the signed message.
    /// @param r The r component.
    /// @param vs The combined vs component (high bit is yParity, lower 255 bits are s).
    /// @return recovered The recovered signer address.
    /// @return err The error enum value.
    /// @return errArg Additional error argument.
    function tryRecover(bytes32 hash, bytes32 r, bytes32 vs)
        internal
        pure
        returns (address recovered, RecoverError err, bytes32 errArg)
    {
        // EIP-2098: yParity is the high bit of vs; s is the lower 255 bits
        bytes32 s = vs & 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        // yParity is 0 or 1; v is 27 + yParity
        uint8 v = uint8((uint256(vs) >> 255) + 27);
        return tryRecover(hash, v, r, s);
    }

    /// @notice Attempts to recover the signer from (v, r, s) components.
    /// @param hash The hash of the signed message.
    /// @param v The recovery byte.
    /// @param r The r component.
    /// @param s The s component.
    /// @return recovered The recovered signer address.
    /// @return err The error enum value.
    /// @return errArg Additional error argument.
    function tryRecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s)
        internal
        pure
        returns (address recovered, RecoverError err, bytes32 errArg)
    {
        // Reject high-S signatures to prevent malleability
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return (address(0), RecoverError.InvalidSignatureS, s);
        }

        recovered = ecrecover(hash, v, r, s);
        if (recovered == address(0)) {
            return (address(0), RecoverError.InvalidSignature, bytes32(0));
        }
        return (recovered, RecoverError.NoError, bytes32(0));
    }

    /// @notice Returns the Ethereum signed message hash of a 32-byte hash.
    /// @dev Produces the hash that would have been signed by eth_sign / personal_sign.
    /// @param hash The original message hash.
    /// @return The prefixed hash: keccak256("\x19Ethereum Signed Message:\n32" ++ hash).
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    /// @notice Returns the Ethereum signed message hash of arbitrary bytes.
    /// @dev Produces keccak256("\x19Ethereum Signed Message:\n{length}" ++ s).
    /// @param s The message bytes.
    /// @return The prefixed hash.
    function toEthSignedMessageHash(bytes memory s) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", _toString(s.length), s));
    }

    /// @notice Returns the EIP-712 typed data hash.
    /// @dev Produces keccak256("\x19\x01" ++ domainSeparator ++ structHash).
    /// @param domainSeparator The EIP-712 domain separator.
    /// @param structHash The hash of the typed data struct.
    /// @return The final digest.
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    /// @dev Throws the appropriate error for a given RecoverError.
    function _throwError(RecoverError err, bytes32 errArg) private pure {
        if (err == RecoverError.NoError) return;
        if (err == RecoverError.InvalidSignature) revert ECDSAInvalidSignature();
        if (err == RecoverError.InvalidSignatureLength) revert ECDSAInvalidSignatureLength(uint256(errArg));
        if (err == RecoverError.InvalidSignatureS) revert ECDSAInvalidSignatureS(errArg);
    }

    /// @dev Converts a uint256 to its decimal ASCII bytes representation.
    function _toString(uint256 value) private pure returns (bytes memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return buffer;
    }
}
