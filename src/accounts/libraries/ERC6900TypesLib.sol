// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HookConfig, ModuleEntity, ValidationConfig, ValidationFlags} from "@lattice/interfaces/external/IERC6900.sol";

/// @title ERC6900TypesLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Pure pack/unpack helpers for the ERC-6900 packed value types {ModuleEntity} / {ValidationConfig} /
///         {HookConfig}. The encodings are the spec (pinned to erc6900/reference-implementation @ 65892c2 — see
///         {IERC6900}); these helpers are written fresh. Layout (big-endian / left-aligned within the type):
///         - ModuleEntity (bytes24):   address module [0..19] ‖ uint32 entityId [20..23]
///         - ValidationConfig (bytes25): ModuleEntity [0..23] ‖ flags [24]
///         - HookConfig (bytes25):       ModuleEntity [0..23] ‖ flags [24]
/// @dev `ValidationConfig` and `HookConfig` share byte 24 but interpret its bits differently — never decode a
///      flag byte with the other type's masks (`_VALIDATION_*` vs `_HOOK_*`).
library ERC6900TypesLib {
    // ValidationConfig flag byte (byte 24).
    uint8 internal constant _VALIDATION_FLAG_IS_USER_OP = 0x01;
    uint8 internal constant _VALIDATION_FLAG_IS_SIGNATURE = 0x02;
    uint8 internal constant _VALIDATION_FLAG_IS_GLOBAL = 0x04;

    // HookConfig flag byte (byte 24). Execution hooks have hook-type bit clear (== 0).
    uint8 internal constant _HOOK_TYPE_VALIDATION = 0x01;
    uint8 internal constant _HOOK_FLAG_HAS_POST = 0x02;
    uint8 internal constant _HOOK_FLAG_HAS_PRE = 0x04;

    // ---- ModuleEntity ----

    function pack(address module_, uint32 entityId_) internal pure returns (ModuleEntity) {
        return ModuleEntity.wrap(bytes24(bytes20(module_)) | bytes24(uint192(entityId_)));
    }

    function unpack(ModuleEntity self) internal pure returns (address module_, uint32 entityId_) {
        bytes24 raw = ModuleEntity.unwrap(self);
        module_ = address(bytes20(raw));
        entityId_ = uint32(bytes4(raw << 160));
    }

    function isEmpty(ModuleEntity self) internal pure returns (bool) {
        return ModuleEntity.unwrap(self) == bytes24(0);
    }

    function eq(ModuleEntity a, ModuleEntity b) internal pure returns (bool) {
        return ModuleEntity.unwrap(a) == ModuleEntity.unwrap(b);
    }

    // ---- ValidationConfig ----

    function pack(address module_, uint32 entityId_, bool isGlobal_, bool isSignatureValidation_, bool isUserOp_)
        internal
        pure
        returns (ValidationConfig)
    {
        return pack(pack(module_, entityId_), isGlobal_, isSignatureValidation_, isUserOp_);
    }

    function pack(ModuleEntity validationFunction, bool isGlobal_, bool isSignatureValidation_, bool isUserOp_)
        internal
        pure
        returns (ValidationConfig)
    {
        uint8 flags = (isGlobal_ ? _VALIDATION_FLAG_IS_GLOBAL : 0)
            | (isSignatureValidation_ ? _VALIDATION_FLAG_IS_SIGNATURE : 0)
            | (isUserOp_ ? _VALIDATION_FLAG_IS_USER_OP : 0);
        return ValidationConfig.wrap(bytes25(ModuleEntity.unwrap(validationFunction)) | bytes25(uint200(flags)));
    }

    function unpack(ValidationConfig self)
        internal
        pure
        returns (ModuleEntity validationFunction, ValidationFlags flags)
    {
        bytes25 raw = ValidationConfig.unwrap(self);
        validationFunction = ModuleEntity.wrap(bytes24(raw));
        flags = ValidationFlags.wrap(uint8(raw[24]));
    }

    function module(ValidationConfig self) internal pure returns (address) {
        return address(bytes20(ValidationConfig.unwrap(self)));
    }

    function entityId(ValidationConfig self) internal pure returns (uint32) {
        return uint32(bytes4(ValidationConfig.unwrap(self) << 160));
    }

    function moduleEntity(ValidationConfig self) internal pure returns (ModuleEntity) {
        return ModuleEntity.wrap(bytes24(ValidationConfig.unwrap(self)));
    }

    function isGlobal(ValidationConfig self) internal pure returns (bool) {
        return (uint8(ValidationConfig.unwrap(self)[24]) & _VALIDATION_FLAG_IS_GLOBAL) != 0;
    }

    function isSignatureValidation(ValidationConfig self) internal pure returns (bool) {
        return (uint8(ValidationConfig.unwrap(self)[24]) & _VALIDATION_FLAG_IS_SIGNATURE) != 0;
    }

    function isUserOpValidation(ValidationConfig self) internal pure returns (bool) {
        return (uint8(ValidationConfig.unwrap(self)[24]) & _VALIDATION_FLAG_IS_USER_OP) != 0;
    }

    // ---- HookConfig ----

    function packValidationHook(ModuleEntity hookFunction) internal pure returns (HookConfig) {
        return HookConfig.wrap(bytes25(ModuleEntity.unwrap(hookFunction)) | bytes25(uint200(_HOOK_TYPE_VALIDATION)));
    }

    function packExecHook(ModuleEntity hookFunction, bool hasPre, bool hasPost) internal pure returns (HookConfig) {
        // Exec hook: hook-type bit stays clear (== 0).
        uint8 flags = (hasPre ? _HOOK_FLAG_HAS_PRE : 0) | (hasPost ? _HOOK_FLAG_HAS_POST : 0);
        return HookConfig.wrap(bytes25(ModuleEntity.unwrap(hookFunction)) | bytes25(uint200(flags)));
    }

    function unpackExecHook(HookConfig self)
        internal
        pure
        returns (ModuleEntity hookFunction, bool hasPre, bool hasPost)
    {
        bytes25 raw = HookConfig.unwrap(self);
        hookFunction = ModuleEntity.wrap(bytes24(raw));
        uint8 flags = uint8(raw[24]);
        hasPre = (flags & _HOOK_FLAG_HAS_PRE) != 0;
        hasPost = (flags & _HOOK_FLAG_HAS_POST) != 0;
    }

    function module(HookConfig self) internal pure returns (address) {
        return address(bytes20(HookConfig.unwrap(self)));
    }

    function entityId(HookConfig self) internal pure returns (uint32) {
        return uint32(bytes4(HookConfig.unwrap(self) << 160));
    }

    function moduleEntity(HookConfig self) internal pure returns (ModuleEntity) {
        return ModuleEntity.wrap(bytes24(HookConfig.unwrap(self)));
    }

    function isValidationHook(HookConfig self) internal pure returns (bool) {
        return (uint8(HookConfig.unwrap(self)[24]) & _HOOK_TYPE_VALIDATION) != 0;
    }

    function hasPreHook(HookConfig self) internal pure returns (bool) {
        return (uint8(HookConfig.unwrap(self)[24]) & _HOOK_FLAG_HAS_PRE) != 0;
    }

    function hasPostHook(HookConfig self) internal pure returns (bool) {
        return (uint8(HookConfig.unwrap(self)[24]) & _HOOK_FLAG_HAS_POST) != 0;
    }
}
