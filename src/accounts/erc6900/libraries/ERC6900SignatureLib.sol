// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    ERC6900ModuleManagerLib,
    ERC6900ModuleManagerStorage
} from "@lattice/accounts/erc6900/libraries/ERC6900ModuleManagerLib.sol";
import {ERC6900TypesLib} from "@lattice/accounts/erc6900/libraries/ERC6900TypesLib.sol";
import {SparseCalldataSegmentLib} from "@lattice/accounts/erc6900/libraries/SparseCalldataSegmentLib.sol";
import {
    ERC1271_INVALID,
    ERC1271_MAGIC_VALUE,
    ERC165_MAP_IERC1271_SLOT,
    ERC7739_SENTINEL_HASH,
    ERC7739_SUPPORT
} from "@lattice/accounts/libraries/ERC1271SignatureLib.sol";
import {ERC7739Lib} from "@lattice/accounts/libraries/ERC7739Lib.sol";
import {IERC6900Validation} from "@lattice/interfaces/accounts/IERC6900Validation.sol";
import {
    HookConfig,
    IERC6900ValidationHookModule,
    IERC6900ValidationModule,
    ModuleEntity,
    ValidationFlags
} from "@lattice/interfaces/external/ercs/IERC6900.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @title ERC6900SignatureLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-6900 reference implementation (https://github.com/erc6900/reference-implementation)
/// @notice The ERC-6900 ERC-1271 signature-validation path: decodes the validation `ModuleEntity` from the
///         signature prefix, runs pre-signature-validation hooks (sparse-segmented), gates on the
///         `isSignatureValidation` flag, and routes to the validation module's `validateSignature`.
/// @dev Re-implemented FRESH from the ERC-6900 reference (erc6900/reference-implementation @ 65892c2). Two Lattice
///      additions over the reference: (1) the 1271 `hash` is first rehashed via ERC-7739 (a nested `TypedDataSign`
///      / `PersonalSign` envelope bound to this account's EIP-712 domain) so a signature can never be replayed
///      against a different account sharing the same signer — the module sees the domain-bound digest, not the
///      raw hash; (2) the ERC-7739 support-detection probe (`isValidSignature(0x7739…, "")`) is answered. The
///      reference 1271 signature layout has NO global flag byte: `signature[0:24]` is the `ModuleEntity` and the
///      sparse-segment blob begins at `[24:]` (vs the userOp path's flag byte at `[24]` and blob at `[25:]`).
library ERC6900SignatureLib {
    using ERC6900TypesLib for ModuleEntity;
    using ERC6900TypesLib for ValidationFlags;
    using ERC6900TypesLib for HookConfig;
    using SparseCalldataSegmentLib for bytes;

    /// @notice Registers the `IERC1271` ERC-165 id.
    function __ERC6900Signature_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC1271_SLOT, true)
        }
    }

    /// @notice ERC-1271 `isValidSignature`. Returns `0x1626ba7e` for a valid (ERC-7739-bound) signature, the
    ///         `0x77390001` support sentinel for the probe, else `0xffffffff`.
    function isValidSignature(bytes32 hash, bytes calldata signature) internal view returns (bytes4) {
        // Account-level ERC-7739 support-detection probe (no ModuleEntity prefix).
        if (hash == ERC7739_SENTINEL_HASH && signature.length == 0) return ERC7739_SUPPORT;

        // signature[0:24] = ModuleEntity; [24:] = sparse-segment blob (NO global flag byte, unlike the userOp path).
        ModuleEntity vf = _moduleEntityOf(signature);
        return _exec1271Validation(vf, hash, _runPreSignatureHooks(vf, hash, signature[24:]));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Runs the validation's pre-signature hooks (each given its sparse segment; a hook revert bubbles), then
    ///      returns the validation function's own (final) signature segment.
    function _runPreSignatureHooks(ModuleEntity vf, bytes32 hash, bytes calldata sig)
        private
        view
        returns (bytes calldata)
    {
        HookConfig[] storage hooks =
        ERC6900ModuleManagerLib.erc6900ModuleManagerStorage()._validations[vf].validationHooks;
        uint256 n = hooks.length;
        for (uint256 i; i < n; ++i) {
            bytes calldata segment;
            (segment, sig) = sig.advanceSegmentIfAtIndex(uint8(i));
            (address module, uint32 entityId) = hooks[i].moduleEntity().unpack();
            IERC6900ValidationHookModule(module).preSignatureValidationHook(entityId, msg.sender, hash, segment);
        }
        return sig.getFinalSegment();
    }

    function _exec1271Validation(ModuleEntity vf, bytes32 hash, bytes calldata finalSig) private view returns (bytes4) {
        if (!ERC6900ModuleManagerLib.erc6900ModuleManagerStorage()._validations[vf].validationFlags
                .isSignatureValidation()) {
            (address module, uint32 entityId) = vf.unpack();
            revert IERC6900Validation.SignatureValidationInvalid(module, entityId);
        }
        // ERC-7739: bind the digest to this account's domain (nested TypedDataSign or PersonalSign), then route to
        // the validation module's `validateSignature`. The module sees the bound digest, never the raw hash.
        if (_validNestedTypedDataSign(vf, hash, finalSig) || _validNestedPersonalSign(vf, hash, finalSig)) {
            return ERC1271_MAGIC_VALUE;
        }
        return ERC1271_INVALID;
    }

    /// @dev `personal_sign`: the module must accept the owner's signature over `hash` wrapped in this account's
    ///      domain. The whole final segment is the module signature.
    function _validNestedPersonalSign(ModuleEntity vf, bytes32 hash, bytes calldata signature)
        private
        view
        returns (bool)
    {
        return _moduleValidates(vf, EIP712Lib.hashTypedDataV4(ERC7739Lib.personalSignStructHash(hash)), signature);
    }

    /// @dev `eth_signTypedData`: the outer `hash` must equal the app's typed-data hash, and the module must accept
    ///      the inner signature over the `TypedDataSign` struct (contents + this account's domain). On a plain
    ///      (non-envelope) signature, `decodeTypedDataSig` fails closed, the hash check is false, and the module
    ///      is not called (falling through to the PersonalSign path).
    function _validNestedTypedDataSign(ModuleEntity vf, bytes32 hash, bytes calldata encodedSignature)
        private
        view
        returns (bool)
    {
        (bytes calldata signature, bytes32 appSeparator, bytes32 contentsHash, string calldata contentsDescr) =
            ERC7739Lib.decodeTypedDataSig(encodedSignature);

        if (hash != _toTypedDataHash(appSeparator, contentsHash) || bytes(contentsDescr).length == 0) return false;

        return _moduleValidates(
            vf,
            _toTypedDataHash(
                appSeparator, ERC7739Lib.typedDataSignStructHash(contentsDescr, contentsHash, _domainBytes())
            ),
            signature
        );
    }

    /// @dev Routes the domain-bound `digest` + inner `signature` to the validation module's `validateSignature`.
    function _moduleValidates(ModuleEntity vf, bytes32 digest, bytes calldata signature) private view returns (bool) {
        (address module, uint32 entityId) = vf.unpack();
        return IERC6900ValidationModule(module)
                .validateSignature(address(this), entityId, msg.sender, digest, signature) == ERC1271_MAGIC_VALUE;
    }

    /// @dev This account's EIP-712 domain, abi-encoded for {ERC7739Lib.typedDataSignStructHash}.
    function _domainBytes() private view returns (bytes memory) {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract, bytes32 salt,) =
            EIP712Lib.eip712Domain();
        return abi.encode(keccak256(bytes(name)), keccak256(bytes(version)), chainId, verifyingContract, salt);
    }

    /// @dev `keccak256("\x19\x01" || separator || structHash)` with the APP's separator.
    function _toTypedDataHash(bytes32 separator, bytes32 structHash) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(hex"1901", separator, structHash));
    }

    function _moduleEntityOf(bytes calldata sig) private pure returns (ModuleEntity me) {
        bytes24 raw;
        assembly ("memory-safe") {
            raw := and(calldataload(sig.offset), 0xffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000)
        }
        me = ModuleEntity.wrap(raw);
    }
}
