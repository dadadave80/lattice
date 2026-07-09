// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAccountSigner
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Admin/read surface of the `AccountSigner` facet — the account's single-owner signer that backs both
///         ERC-4337 `validateUserOp` and ERC-1271 `isValidSignature`. ECDSA is the default/legacy scheme; a
///         P256 (secp256r1) raw key or a WebAuthn passkey may be set as the owner instead.
/// @dev For ECDSA the owner may be an EOA or an ERC-1271 contract (validation routes through the repo's
///      `SignatureChecker`). `owner()` is authoritative only when `signerType() == ECDSA`.
interface IAccountSigner {
    /// @notice The signature scheme backing the account owner. `ECDSA` (0) is the default on every account.
    enum SignerType {
        ECDSA,
        P256,
        WebAuthn
    }

    /// @notice Emitted when the ECDSA signing owner changes (also re-arms the ECDSA scheme).
    event OwnerSet(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when a raw P256 (secp256r1) public key is set as the owner.
    event P256SignerSet(bytes32 x, bytes32 y);

    /// @notice Emitted when a WebAuthn passkey (P256 public key + UV policy) is set as the owner.
    event WebAuthnSignerSet(bytes32 x, bytes32 y, bool requireUserVerification);

    /// @notice The new owner is the zero address.
    error InvalidOwner();

    /// @notice The P256 public key is (0, 0).
    error InvalidP256Key();

    /// @notice The ECDSA owner. Authoritative only when `signerType() == ECDSA`.
    function owner() external view returns (address);

    /// @notice The active signature scheme.
    function signerType() external view returns (SignerType);

    /// @notice The P256/WebAuthn public key coordinates (zero unless a passkey owner is set).
    function p256PublicKey() external view returns (bytes32 x, bytes32 y);

    /// @notice Whether WebAuthn assertions must carry the User-Verified flag.
    function requireUserVerification() external view returns (bool);

    /// @notice Sets an ECDSA owner (EOA or ERC-1271). Resets the scheme to ECDSA. Admin only.
    function setOwner(address newOwner) external;

    /// @notice Sets a raw P256 (secp256r1) public key as the owner. Admin only.
    function setP256Signer(bytes32 x, bytes32 y) external;

    /// @notice Sets a WebAuthn passkey (P256 key + UV policy) as the owner. Admin only.
    function setWebAuthnSigner(bytes32 x, bytes32 y, bool requireUserVerification) external;
}
