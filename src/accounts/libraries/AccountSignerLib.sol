// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccountSigner} from "@lattice/interfaces/accounts/IAccountSigner.sol";
import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {P256} from "@lattice/utils/libraries/P256.sol";
import {SignatureChecker} from "@lattice/utils/libraries/SignatureChecker.sol";
import {WebAuthn} from "@lattice/utils/libraries/WebAuthn.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.AccountSigner")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ACCOUNT_SIGNER_STORAGE_SLOT = 0x0da6d1e39c7e91c8bb664dbc699f525d1effdcf9e745a754a440ffebe67feb00;

/// @notice ERC-7201 namespaced storage for the account's single-owner signer.
/// @custom:storage-location erc7201:lattice.storage.AccountSigner
struct AccountSignerStorage {
    /// @notice ECDSA owner (EOA or ERC-1271). Authoritative only when `_signerType == ECDSA`. APPEND-ONLY.
    address _owner;
    /// @notice Active signature scheme as `uint8(SignerType)` (0 == ECDSA). Stored as `uint8`, not the enum,
    ///         so the inspected storage layout is reproducible (`t_enum` carries a non-deterministic solc AST
    ///         id, which breaks the cross-machine layout baseline). Packs into slot 0 above `_owner`. APPEND-ONLY.
    uint8 _signerType;
    /// @notice WebAuthn user-verification policy. Packs into slot 0. APPEND-ONLY.
    bool _requireUV;
    /// @notice P256/WebAuthn public key X. APPEND-ONLY.
    bytes32 _p256X;
    /// @notice P256/WebAuthn public key Y. APPEND-ONLY.
    bytes32 _p256Y;
}

/// @title AccountSignerLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic + ERC-7201 storage for the account's single owner, backing both ERC-4337 `validateUserOp`
///         and ERC-1271 `isValidSignature`. ECDSA is the default scheme; a P256 raw key or a WebAuthn passkey
///         can be set as the owner instead.
/// @dev `isValidSignatureNow` is the signer seam consumed unchanged by the validation / 1271 / executor facets.
///      It dispatches on the STORED signer type (not the signature shape) and never reverts on malformed input
///      (returns false), so the 4337 path yields `SIG_VALIDATION_FAILED` rather than reverting. P256/WebAuthn
///      verification is delegated to vendored audited Solady libs (RIP-7212 precompile with a verifier fallback;
///      low-S enforced). The ECDSA branch is byte-for-byte the legacy path.
library AccountSignerLib {
    function accountSignerStorage() internal pure returns (AccountSignerStorage storage $) {
        assembly {
            $.slot := ACCOUNT_SIGNER_STORAGE_SLOT
        }
    }

    /// @notice Seeds the ECDSA signing owner during diamond initialization.
    function __AccountSigner_init(address owner_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        _setOwner(owner_);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function owner() internal view returns (address) {
        return accountSignerStorage()._owner;
    }

    function signerType() internal view returns (IAccountSigner.SignerType) {
        return IAccountSigner.SignerType(accountSignerStorage()._signerType);
    }

    function p256PublicKey() internal view returns (bytes32 x, bytes32 y) {
        AccountSignerStorage storage $ = accountSignerStorage();
        return ($._p256X, $._p256Y);
    }

    function requireUserVerification() internal view returns (bool) {
        return accountSignerStorage()._requireUV;
    }

    /// @notice True if `signature` is valid over `hash` for the configured owner (ECDSA / P256 / WebAuthn).
    function isValidSignatureNow(bytes32 hash, bytes memory signature) internal view returns (bool) {
        AccountSignerStorage storage $ = accountSignerStorage();
        IAccountSigner.SignerType t = IAccountSigner.SignerType($._signerType);

        if (t == IAccountSigner.SignerType.ECDSA) {
            address o = $._owner;
            // EIP-7702 self-owner (#58 item 7): when the owner IS this account, the account is its own signing
            // EOA and now carries delegate code. Running a bad signature through SignatureChecker would fall
            // through to this same account's ERC-1271 path and recurse, burning gas up to the call's limit
            // (breaking the "never reverts, fails cheaply" invariant the 4337 path relies on). A self-owner is
            // an EOA key by construction, so verify with plain ECDSA recovery only — no ERC-1271 fallback.
            if (o == address(this)) {
                (address rec, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
                return err == ECDSA.RecoverError.NoError && rec == o;
            }
            // Legacy path, byte-for-byte: EOA (ECDSA, low-S enforced) or ERC-1271 owner.
            return SignatureChecker.isValidSignatureNow(o, hash, signature);
        }

        if (t == IAccountSigner.SignerType.P256) {
            if (signature.length != 64) return false; // length guard — never revert
            bytes32 r;
            bytes32 s;
            assembly ("memory-safe") {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
            }
            return P256.verifySignature(hash, r, s, $._p256X, $._p256Y); // low-S enforced
        }

        // WebAuthn: `signature` is the COMPACT assertion encoding (see {WebAuthn.tryEncodeAuthCompact}):
        // `abi.encodePacked(uint16 authDataLen, authData, clientDataJSON, uint16 challengeIndex, uint16 typeIndex,
        // bytes32 r, bytes32 s)` — chosen over the ABI envelope to shave UserOp calldata. The decoder never
        // reverts (a malformed envelope yields an empty struct → verify returns false). `hash` is the raw
        // challenge — WebAuthn.verify base64url-encodes it and matches it inside clientDataJSON; no pre-hash.
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.tryDecodeAuthCompact(signature);
        return WebAuthn.verify(abi.encodePacked(hash), $._requireUV, auth, $._p256X, $._p256Y);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets an ECDSA owner and re-arms the ECDSA scheme. Admin only.
    function setOwner(address newOwner) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setOwner(newOwner);
    }

    /// @notice Sets a raw P256 (secp256r1) public key as the owner. Admin only.
    function setP256Signer(bytes32 x, bytes32 y) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setSigner(IAccountSigner.SignerType.P256, x, y, false);
    }

    /// @notice Sets a WebAuthn passkey (P256 key + UV policy) as the owner. Admin only.
    function setWebAuthnSigner(bytes32 x, bytes32 y, bool requireUV) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setSigner(IAccountSigner.SignerType.WebAuthn, x, y, requireUV);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    function _setOwner(address newOwner) private {
        if (newOwner == address(0)) revert IAccountSigner.InvalidOwner();
        AccountSignerStorage storage $ = accountSignerStorage();
        emit IAccountSigner.OwnerSet($._owner, newOwner);
        $._owner = newOwner;
        $._signerType = uint8(IAccountSigner.SignerType.ECDSA); // re-arm the ECDSA path on owner change
    }

    function _setSigner(IAccountSigner.SignerType t, bytes32 x, bytes32 y, bool uv) private {
        if (x == bytes32(0) && y == bytes32(0)) revert IAccountSigner.InvalidP256Key();
        AccountSignerStorage storage $ = accountSignerStorage();
        $._signerType = uint8(t);
        $._p256X = x;
        $._p256Y = y;
        $._requireUV = uv;
        if (t == IAccountSigner.SignerType.P256) emit IAccountSigner.P256SignerSet(x, y);
        else emit IAccountSigner.WebAuthnSignerSet(x, y, uv);
    }
}
