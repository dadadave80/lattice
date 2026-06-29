// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC6900ExecutorLib, ValidationCheckType} from "@lattice/accounts/erc6900/libraries/ERC6900ExecutorLib.sol";
import {
    ERC6900ModuleManagerLib,
    ERC6900ModuleManagerStorage,
    ValidationStorage
} from "@lattice/accounts/erc6900/libraries/ERC6900ModuleManagerLib.sol";
import {ERC6900TypesLib} from "@lattice/accounts/erc6900/libraries/ERC6900TypesLib.sol";
import {SparseCalldataSegmentLib} from "@lattice/accounts/erc6900/libraries/SparseCalldataSegmentLib.sol";
import {ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {IERC6900Executor} from "@lattice/interfaces/accounts/IERC6900Executor.sol";
import {IERC6900Validation} from "@lattice/interfaces/accounts/IERC6900Validation.sol";
import {PackedUserOperation} from "@lattice/interfaces/external/IAccount.sol";
import {
    HookConfig,
    IERC6900ValidationHookModule,
    IERC6900ValidationModule,
    ModuleEntity,
    ValidationFlags
} from "@lattice/interfaces/external/IERC6900.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";

/// @title ERC6900ValidationLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The ERC-6900 ERC-4337 userOp validation path: decodes the validation `ModuleEntity` from the userOp
///         signature prefix, checks applicability (reusing the executor's gate), runs pre-userOp-validation hooks
///         (sparse-segmented), gates on the `isUserOpValidation` flag, calls the validation module's
///         `validateUserOp`, coalesces the results, and pays the EntryPoint prefund.
/// @dev Re-implemented FRESH from the ERC-6900 reference (erc6900/reference-implementation @ 65892c2). The
///      validating `ModuleEntity` + global flag come from `userOp.signature[0:24]` / `[24]` (NOT the nonce — the
///      reference never reads it); `[25:]` is the sparse-segment blob distributing per-hook signatures. The
///      EntryPoint is the one shared with the ERC-4337 facet ({ERC4337ValidationLib} — the executor's bypass
///      reads the same slot). Validation-associated EXECUTION hooks (which need the `executeUserOp` wrapper at
///      execution time) are not yet supported and are rejected ({RequireUserOperationContext}) rather than
///      silently skipped.
library ERC6900ValidationLib {
    using ERC6900TypesLib for ModuleEntity;
    using ERC6900TypesLib for ValidationFlags;
    using ERC6900TypesLib for HookConfig;
    using SparseCalldataSegmentLib for bytes;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice ERC-4337 account validation for the ERC-6900 account. Only the configured EntryPoint may call.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        internal
        returns (uint256 validationData)
    {
        if (msg.sender != ERC4337ValidationLib.entryPoint()) revert IERC6900Validation.NotFromEntryPoint(msg.sender);
        validationData = _validateUserOp(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    function _validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) private returns (uint256) {
        if (userOp.callData.length < 4) revert IERC6900Executor.UnrecognizedFunction(_selectorOf(userOp.callData));

        // ModuleEntity[0:24] ‖ isGlobal flag[24] (==1 ⇒ global) ‖ sparse-segment blob[25:]. Reading [24] first
        // bounds-checks signature.length >= 25 before the (unchecked) assembly read of [0:24].
        bool isGlobal = uint8(userOp.signature[24]) == 1;
        ModuleEntity vf = _moduleEntityOf(userOp.signature);

        ERC6900ExecutorLib.checkValidationAppliesCallData(
            userOp.callData, vf, isGlobal ? ValidationCheckType.GLOBAL : ValidationCheckType.SELECTOR
        );

        ValidationStorage storage v = ERC6900ModuleManagerLib.erc6900ModuleManagerStorage()._validations[vf];
        if (v.executionHooks.length() > 0) revert IERC6900Validation.RequireUserOperationContext();

        return _doUserOpValidation(vf, v, userOp, userOp.signature[25:], userOpHash);
    }

    function _doUserOpValidation(
        ModuleEntity vf,
        ValidationStorage storage v,
        PackedUserOperation calldata userOpCd,
        bytes calldata signature,
        bytes32 userOpHash
    ) private returns (uint256 validationRes) {
        HookConfig[] storage hooks = v.validationHooks;
        uint256 n = hooks.length;
        // A memory copy whose `signature` field is rewritten to each hook's segment (and to the final segment for
        // the validation function itself).
        PackedUserOperation memory userOp = userOpCd;
        for (uint256 i; i < n; ++i) {
            bytes calldata segment;
            (segment, signature) = signature.advanceSegmentIfAtIndex(uint8(i));
            userOp.signature = segment;
            (address module, uint32 entityId) = hooks[i].moduleEntity().unpack();
            uint256 res = IERC6900ValidationHookModule(module).preUserOpValidationHook(entityId, userOp, userOpHash);
            // A hook may signal success/failure (0/1) but may NOT delegate to an aggregator.
            if (uint160(res) > 1) {
                revert IERC6900Validation.UnexpectedAggregator(module, entityId, address(uint160(res)));
            }
            validationRes = _coalescePreValidation(validationRes, res);
        }
        userOp.signature = signature.getFinalSegment();
        uint256 mainRes = _execUserOpValidation(vf, v, userOp, userOpHash);
        validationRes = n != 0 ? _coalesceValidation(validationRes, mainRes) : mainRes;
    }

    function _execUserOpValidation(
        ModuleEntity vf,
        ValidationStorage storage v,
        PackedUserOperation memory userOp,
        bytes32 userOpHash
    ) private returns (uint256) {
        (address module, uint32 entityId) = vf.unpack();
        if (!v.validationFlags.isUserOpValidation()) {
            revert IERC6900Validation.UserOpValidationInvalid(module, entityId);
        }
        return IERC6900ValidationModule(module).validateUserOp(entityId, userOp, userOpHash);
    }

    /// @dev Intersect two pre-validation results: validUntil = MIN (0 ⇒ no-expiry sentinel), validAfter = MAX,
    ///      authorizer = OR (safe: each is 0 or 1, enforced by the {UnexpectedAggregator} guard).
    function _coalescePreValidation(uint256 a, uint256 b) private pure returns (uint256 res) {
        uint48 validUntilA = uint48(a >> 160);
        if (validUntilA == 0) validUntilA = type(uint48).max;
        uint48 validUntilB = uint48(b >> 160);
        if (validUntilB == 0) validUntilB = type(uint48).max;
        res = uint256(validUntilA > validUntilB ? validUntilB : validUntilA) << 160;
        uint48 validAfterA = uint48(a >> 208);
        uint48 validAfterB = uint48(b >> 208);
        res |= uint256(validAfterA < validAfterB ? validAfterB : validAfterA) << 208;
        res |= uint160(a) | uint160(b);
    }

    /// @dev Combine the coalesced hook result with the validation-function result. Time ranges intersect as in
    ///      {_coalescePreValidation}; authorizer is asymmetric — a failing hook (authorizer 1) vetoes, otherwise
    ///      the validation function's authorizer (which MAY be a real aggregator) passes through.
    function _coalesceValidation(uint256 pre, uint256 mainRes) private pure returns (uint256 res) {
        uint48 validUntilA = uint48(pre >> 160);
        if (validUntilA == 0) validUntilA = type(uint48).max;
        uint48 validUntilB = uint48(mainRes >> 160);
        if (validUntilB == 0) validUntilB = type(uint48).max;
        res = uint256(validUntilA > validUntilB ? validUntilB : validUntilA) << 160;
        uint48 validAfterA = uint48(pre >> 208);
        uint48 validAfterB = uint48(mainRes >> 208);
        res |= uint256(validAfterA < validAfterB ? validAfterB : validAfterA) << 208;
        res |= uint160(pre) == 1 ? 1 : uint160(mainRes);
    }

    /// @dev Pays the EntryPoint (`msg.sender`) its prefund; result ignored (the EntryPoint validates its own
    ///      balance change, and reverting here would block validation).
    function _payPrefund(uint256 missingAccountFunds) private {
        if (missingAccountFunds != 0) {
            assembly ("memory-safe") {
                pop(call(gas(), caller(), missingAccountFunds, 0x00, 0x00, 0x00, 0x00))
            }
        }
    }

    function _moduleEntityOf(bytes calldata sig) private pure returns (ModuleEntity me) {
        bytes24 raw;
        assembly ("memory-safe") {
            raw := and(calldataload(sig.offset), 0xffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000)
        }
        me = ModuleEntity.wrap(raw);
    }

    function _selectorOf(bytes calldata data) private pure returns (bytes4 s) {
        assembly ("memory-safe") {
            s := and(calldataload(data.offset), 0xffffffff00000000000000000000000000000000000000000000000000000000)
        }
    }
}
