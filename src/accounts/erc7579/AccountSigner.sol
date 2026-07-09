// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {IAccountSigner} from "@lattice/interfaces/accounts/IAccountSigner.sol";

/// @title AccountSigner
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Single-owner signer facet. The configured owner's signatures authorize ERC-4337 `validateUserOp`
///         (see `ERC4337Validation`) and ERC-1271 `isValidSignature` (see `ERC1271Signature`). ECDSA is the
///         default scheme; a P256 (secp256r1) raw key or a WebAuthn passkey can be set as the owner instead.
/// @dev Stateless delegator — logic/storage live in {AccountSignerLib}. The ECDSA owner may be an EOA or an
///      ERC-1271 contract; passkey verification uses the vendored audited Solady P256/WebAuthn libs.
/// @custom:lattice-version 0.2.0
contract AccountSigner is IAccountSigner {
    /// @inheritdoc IAccountSigner
    function owner() external view virtual returns (address) {
        return AccountSignerLib.owner();
    }

    /// @inheritdoc IAccountSigner
    function signerType() external view virtual returns (SignerType) {
        return AccountSignerLib.signerType();
    }

    /// @inheritdoc IAccountSigner
    function p256PublicKey() external view virtual returns (bytes32 x, bytes32 y) {
        return AccountSignerLib.p256PublicKey();
    }

    /// @inheritdoc IAccountSigner
    function requireUserVerification() external view virtual returns (bool) {
        return AccountSignerLib.requireUserVerification();
    }

    /// @inheritdoc IAccountSigner
    function setOwner(address newOwner) external virtual {
        AccountSignerLib.setOwner(newOwner);
    }

    /// @inheritdoc IAccountSigner
    function setP256Signer(bytes32 x, bytes32 y) external virtual {
        AccountSignerLib.setP256Signer(x, y);
    }

    /// @inheritdoc IAccountSigner
    function setWebAuthnSigner(bytes32 x, bytes32 y, bool requireUserVerification_) external virtual {
        AccountSignerLib.setWebAuthnSigner(x, y, requireUserVerification_);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect AccountSigner methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `owner()` 0x8da5cb5b
    ///      `p256PublicKey()` 0x29ede33c
    ///      `requireUserVerification()` 0x90d1a7de
    ///      `setOwner(address)` 0x13af4035
    ///      `setP256Signer(bytes32,bytes32)` 0x0987050a
    ///      `setWebAuthnSigner(bytes32,bytes32,bool)` 0x2c87b6e5
    ///      `signerType()` 0x37d694aa
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"8da5cb5b29ede33c90d1a7de13af40350987050a2c87b6e537d694aa";
    }
}
