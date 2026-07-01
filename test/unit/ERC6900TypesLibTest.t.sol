// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC6900TypesLib} from "@lattice/accounts/erc6900/libraries/ERC6900TypesLib.sol";
import {HookConfig, ModuleEntity, ValidationConfig, ValidationFlags} from "@lattice/interfaces/external/IERC6900.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Locks the ERC-6900 packed-type encodings bit-for-bit against the spec. The golden vectors use a module
///      address and entityId with no zero bytes, so a wrong shift or mask cannot accidentally round-trip.
contract ERC6900TypesLibTest is Test {
    using ERC6900TypesLib for ModuleEntity;
    using ERC6900TypesLib for ValidationConfig;
    using ERC6900TypesLib for ValidationFlags;
    using ERC6900TypesLib for HookConfig;

    address constant MODULE = 0xAAbbCCDdeEFf00112233445566778899aABBcCDd;
    uint32 constant ENTITY_ID = 0x12345678;
    bytes24 constant ME_GOLDEN = 0xAABBCCDDEEFF00112233445566778899AABBCCDD12345678;

    function _flag(bytes25 b) internal pure returns (bytes1) {
        return b[24];
    }

    // ---- ModuleEntity (address ‖ entityId) ----

    function test_ModuleEntity_GoldenLayout() public pure {
        assertEq(ModuleEntity.unwrap(ERC6900TypesLib.pack(MODULE, ENTITY_ID)), ME_GOLDEN, "ME layout");
    }

    function test_ModuleEntity_RoundTrip() public pure {
        (address m, uint32 e) = ERC6900TypesLib.pack(MODULE, ENTITY_ID).unpack();
        assertEq(m, MODULE, "module");
        assertEq(e, ENTITY_ID, "entityId");
    }

    function testFuzz_ModuleEntity_RoundTrip(address m, uint32 e) public pure {
        (address m2, uint32 e2) = ERC6900TypesLib.pack(m, e).unpack();
        assertEq(m2, m, "module");
        assertEq(e2, e, "entityId");
    }

    function test_ModuleEntity_EmptyAndEq() public pure {
        assertTrue(ModuleEntity.wrap(0).isEmpty(), "zero is empty");
        assertFalse(ERC6900TypesLib.pack(MODULE, ENTITY_ID).isEmpty(), "nonzero not empty");
        assertTrue(ERC6900TypesLib.pack(MODULE, ENTITY_ID).eq(ERC6900TypesLib.pack(MODULE, ENTITY_ID)), "eq");
        assertFalse(ERC6900TypesLib.pack(MODULE, ENTITY_ID).eq(ERC6900TypesLib.pack(MODULE, ENTITY_ID + 1)), "neq");
    }

    // ---- ValidationConfig (ModuleEntity ‖ flags) ----

    function _vc(bool g, bool s, bool u) internal pure returns (ValidationConfig) {
        return ERC6900TypesLib.pack(MODULE, ENTITY_ID, g, s, u);
    }

    function test_ValidationConfig_FlagByteIsolation() public pure {
        assertEq(_flag(ValidationConfig.unwrap(_vc(true, false, false))), bytes1(0x04), "isGlobal=0x04");
        assertEq(_flag(ValidationConfig.unwrap(_vc(false, true, false))), bytes1(0x02), "isSignature=0x02");
        assertEq(_flag(ValidationConfig.unwrap(_vc(false, false, true))), bytes1(0x01), "isUserOp=0x01");
        assertEq(_flag(ValidationConfig.unwrap(_vc(true, true, true))), bytes1(0x07), "all=0x07");
    }

    function test_ValidationConfig_GoldenLayout() public pure {
        bytes25 expected = bytes25(abi.encodePacked(ME_GOLDEN, bytes1(0x07)));
        assertEq(ValidationConfig.unwrap(_vc(true, true, true)), expected, "VC layout");
    }

    function test_ValidationConfig_Accessors() public pure {
        ValidationConfig cfg = _vc(true, false, true);
        assertEq(cfg.module(), MODULE, "module");
        assertEq(cfg.entityId(), ENTITY_ID, "entityId");
        assertEq(ModuleEntity.unwrap(cfg.moduleEntity()), ME_GOLDEN, "moduleEntity");
        assertTrue(cfg.isGlobal(), "isGlobal");
        assertFalse(cfg.isSignatureValidation(), "isSignature");
        assertTrue(cfg.isUserOpValidation(), "isUserOp");
    }

    function test_ValidationConfig_Unpack() public pure {
        (ModuleEntity me, ValidationFlags flags) = _vc(true, false, true).unpack();
        assertEq(ModuleEntity.unwrap(me), ME_GOLDEN, "moduleEntity");
        assertEq(ValidationFlags.unwrap(flags), 0x05, "flags = isGlobal|isUserOp");
    }

    function test_ValidationFlags_Accessors() public pure {
        (, ValidationFlags g) = _vc(true, false, false).unpack();
        assertTrue(g.isGlobal() && !g.isSignatureValidation() && !g.isUserOpValidation(), "isGlobal only");
        (, ValidationFlags s) = _vc(false, true, false).unpack();
        assertTrue(!s.isGlobal() && s.isSignatureValidation() && !s.isUserOpValidation(), "isSignature only");
        (, ValidationFlags u) = _vc(false, false, true).unpack();
        assertTrue(!u.isGlobal() && !u.isSignatureValidation() && u.isUserOpValidation(), "isUserOp only");
    }

    function test_ValidationConfig_PackFromModuleEntity() public pure {
        ModuleEntity me = ERC6900TypesLib.pack(MODULE, ENTITY_ID);
        assertEq(
            ValidationConfig.unwrap(ERC6900TypesLib.pack(me, true, true, true)),
            ValidationConfig.unwrap(_vc(true, true, true)),
            "pack(ME,...) == pack(addr,id,...)"
        );
    }

    // ---- HookConfig (ModuleEntity ‖ flags) ----

    function test_HookConfig_ValidationHook() public pure {
        HookConfig hc = ERC6900TypesLib.packValidationHook(ERC6900TypesLib.pack(MODULE, ENTITY_ID));
        assertEq(_flag(HookConfig.unwrap(hc)), bytes1(0x01), "validation-hook flag=0x01");
        assertTrue(hc.isValidationHook(), "isValidationHook");
        assertFalse(hc.hasPreHook(), "no pre");
        assertFalse(hc.hasPostHook(), "no post");
        assertEq(hc.module(), MODULE, "module");
        assertEq(hc.entityId(), ENTITY_ID, "entityId");
    }

    function test_HookConfig_ExecHook_FlagIsolation() public pure {
        ModuleEntity me = ERC6900TypesLib.pack(MODULE, ENTITY_ID);
        assertEq(_flag(HookConfig.unwrap(ERC6900TypesLib.packExecHook(me, true, false))), bytes1(0x04), "hasPre=0x04");
        assertEq(_flag(HookConfig.unwrap(ERC6900TypesLib.packExecHook(me, false, true))), bytes1(0x02), "hasPost=0x02");
        assertEq(_flag(HookConfig.unwrap(ERC6900TypesLib.packExecHook(me, true, true))), bytes1(0x06), "both=0x06");
        assertEq(_flag(HookConfig.unwrap(ERC6900TypesLib.packExecHook(me, false, false))), bytes1(0x00), "none=0x00");
    }

    function test_HookConfig_ExecHook_RoundTrip() public pure {
        ModuleEntity me = ERC6900TypesLib.pack(MODULE, ENTITY_ID);
        HookConfig hc = ERC6900TypesLib.packExecHook(me, true, false);
        (ModuleEntity me2, bool hasPre, bool hasPost) = hc.unpackExecHook();
        assertTrue(ERC6900TypesLib.eq(me, me2), "moduleEntity");
        assertTrue(hasPre, "pre");
        assertFalse(hasPost, "post");
        assertFalse(hc.isValidationHook(), "exec hook is not a validation hook");
    }
}
