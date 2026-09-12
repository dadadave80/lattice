// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAccountSigner
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Admin/read surface of the `AccountSigner` facet — the account's single-owner signer that backs both
///         ERC-4337 `validateUserOp` and ERC-1271 `isValidSignature`. ECDSA is the default/legacy scheme; a
///         P256 (secp256r1) raw key, a WebAuthn passkey, or a native Hedera account may be set as the owner
///         instead.
/// @dev For ECDSA the owner may be an EOA or an ERC-1271 contract (validation routes through the repo's
///      `SignatureChecker`). `owner()` is authoritative when `signerType()` is `ECDSA` or `HederaAccount` —
///      both store an address; the passkey schemes store a key pair instead.
interface IAccountSigner {
    /// @notice The signature scheme backing the account owner. `ECDSA` (0) is the default on every account.
    /// @dev APPEND-ONLY. The active scheme is persisted as a `uint8`, so a new scheme MUST be appended as the
    ///      LAST value: reordering or inserting one would silently retype every live account's stored scheme.
    enum SignerType {
        ECDSA,
        P256,
        WebAuthn,
        HederaAccount
    }

    /// @notice Emitted when the ECDSA signing owner changes (also re-arms the ECDSA scheme).
    event OwnerSet(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when a raw P256 (secp256r1) public key is set as the owner.
    event P256SignerSet(bytes32 x, bytes32 y);

    /// @notice Emitted when a WebAuthn passkey (P256 public key + UV policy) is set as the owner.
    event WebAuthnSignerSet(bytes32 x, bytes32 y, bool requireUserVerification);

    /// @notice Emitted when a native Hedera account is set as the owner.
    event HederaAccountSignerSet(address indexed account);

    /// @notice The new owner is the zero address.
    error InvalidOwner();

    /// @notice The P256 public key is (0, 0).
    error InvalidP256Key();

    /// @notice The Hedera Account Service system contract is not live on this chain, so a Hedera signer
    ///         could never verify anything and arming one would strand the account.
    error HederaAccountServiceUnavailable();

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

    /// @notice Sets a native Hedera account (ED25519 or ECDSA key) as the owner: signatures are verified by
    ///         the Hedera Account Service system contract (HIP-632), so no key material is stored. Admin only.
    /// @dev Reverts {HederaAccountServiceUnavailable} on a chain where HAS does not answer. That guard is
    ///      load-bearing, not defensive: a Lattice account is its OWN `DEFAULT_ADMIN_ROLE` holder
    ///      ({AccountInit} seeds `address(this)`), so every admin call — including {setOwner}, the only way
    ///      back to ECDSA — has to pass the signer that this call replaces. Arming a Hedera signer where HAS
    ///      is dead would make every signature `false` and leave no authority able to undo it: the account,
    ///      its owner change and its `diamondCut` upgrade path would all be permanently stranded.
    /// @param account The Hedera account's EVM alias or long-zero `0x000…<accountNum>` address.
    function setHederaAccountSigner(address account) external;
}
