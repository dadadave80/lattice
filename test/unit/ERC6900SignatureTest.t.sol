// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC6900ModuleManager} from "@lattice/accounts/erc6900/ERC6900ModuleManager.sol";
import {ERC6900Signature} from "@lattice/accounts/erc6900/ERC6900Signature.sol";
import {ERC6900TypesLib} from "@lattice/accounts/erc6900/libraries/ERC6900TypesLib.sol";
import {
    ERC1271_INVALID,
    ERC1271_MAGIC_VALUE,
    ERC7739_SENTINEL_HASH,
    ERC7739_SUPPORT
} from "@lattice/accounts/libraries/ERC1271SignatureLib.sol";
import {ERC7739Lib} from "@lattice/accounts/libraries/ERC7739Lib.sol";
import {IERC6900Validation} from "@lattice/interfaces/accounts/IERC6900Validation.sol";
import {HookConfig, ModuleEntity, ValidationConfig} from "@lattice/interfaces/external/IERC6900.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @dev A staticcall-safe (view) signature-validation module: returns MAGIC only if it receives a hash equal to
///      a preset, so a test can assert the account handed it the 7739-WRAPPED digest, not the raw hash.
contract MockSigValidation {
    bytes32 public expected;

    function setExpected(bytes32 e) external {
        expected = e;
    }

    function validateSignature(address, uint32, address, bytes32 hash, bytes calldata) external view returns (bytes4) {
        return hash == expected ? ERC1271_MAGIC_VALUE : ERC1271_INVALID;
    }

    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function moduleId() external pure returns (string memory) {
        return "lattice.mocksig.1.0.0";
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

/// @dev A pre-signature hook that reverts with the args it saw, so a test can prove it ran with the raw hash,
///      the 1271 caller, and its signature segment.
contract MockSigHook {
    error HookSaw(bytes32 hash, address sender, bytes sig);

    function preSignatureValidationHook(uint32, address sender, bytes32 hash, bytes calldata signature) external pure {
        revert HookSaw(hash, sender, signature);
    }

    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function moduleId() external pure returns (string memory) {
        return "lattice.mocksighook.1.0.0";
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

contract MockSigAccount is AccessControl, ERC6900ModuleManager, ERC6900Signature {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, ERC6900ModuleManager, ERC6900Signature)
        returns (bytes memory)
    {}

    function initialize(address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        EIP712Lib.__EIP712_init("LatticeAccount6900", "1");
        InitializableLib.postInitializer(s);
    }

    /// @dev The ERC-7739 PersonalSign digest the account binds a raw hash to (for asserting the composition).
    function wrap(bytes32 h) external view returns (bytes32) {
        return EIP712Lib.hashTypedDataV4(ERC7739Lib.personalSignStructHash(h));
    }
}

contract ERC6900SignatureTest is Test {
    MockSigAccount account;
    MockSigValidation val;
    address admin = address(0xA11CE);
    address signer = address(0x5167E2);

    uint32 constant ENTITY = 7;
    bytes32 constant RAW_HASH = keccak256("some app digest");

    function setUp() public {
        account = new MockSigAccount();
        account.initialize(admin);
        val = new MockSigValidation();
    }

    function _me() internal view returns (ModuleEntity) {
        return ERC6900TypesLib.pack(address(val), ENTITY);
    }

    function _install(bool isSig, bytes[] memory hooks) internal {
        // 1271 gates only on isSignatureValidation; global/selectors are irrelevant.
        ValidationConfig cfg = ERC6900TypesLib.pack(address(val), ENTITY, false, isSig, false);
        vm.prank(admin);
        account.installValidation(cfg, new bytes4[](0), "", hooks);
    }

    /// @dev signature = ModuleEntity(24) ‖ 0xFF final-segment marker ‖ rawSig (no hooks).
    function _sig(bytes memory rawSig) internal view returns (bytes memory) {
        return abi.encodePacked(ModuleEntity.unwrap(_me()), bytes1(0xff), rawSig);
    }

    function _isValid(bytes32 hash, bytes memory sig) internal view returns (bytes4) {
        return account.isValidSignature(hash, sig);
    }

    function test_IsValidSignature_RoutesWith7739Binding() public {
        _install(true, new bytes[](0));
        val.setExpected(account.wrap(RAW_HASH)); // module accepts ONLY the domain-bound digest
        assertEq(_isValid(RAW_HASH, _sig(hex"1234")), ERC1271_MAGIC_VALUE, "valid 7739-bound signature");
    }

    function test_IsValidSignature_RawHashIsNotPassedToModule() public {
        _install(true, new bytes[](0));
        val.setExpected(RAW_HASH); // module would accept only the RAW hash — which it must never receive
        assertEq(_isValid(RAW_HASH, _sig(hex"1234")), ERC1271_INVALID, "raw hash must be 7739-wrapped first");
    }

    function test_IsValidSignature_ModuleRejects() public {
        _install(true, new bytes[](0));
        val.setExpected(bytes32(0)); // never matches
        assertEq(_isValid(RAW_HASH, _sig(hex"1234")), ERC1271_INVALID, "rejected signature");
    }

    function test_IsValidSignature_RevertNotSignatureFlag() public {
        _install(false, new bytes[](0)); // installed without the isSignatureValidation flag
        vm.expectRevert(
            abi.encodeWithSelector(IERC6900Validation.SignatureValidationInvalid.selector, address(val), ENTITY)
        );
        account.isValidSignature(RAW_HASH, _sig(hex"1234"));
    }

    function test_IsValidSignature_SupportSentinel() public view {
        assertEq(account.isValidSignature(ERC7739_SENTINEL_HASH, ""), ERC7739_SUPPORT, "ERC-7739 support probe");
    }

    function test_IsValidSignature_RunsPreSignatureHook() public {
        MockSigHook hook = new MockSigHook();
        bytes[] memory hooks = new bytes[](1);
        hooks[0] = abi.encodePacked(
            HookConfig.unwrap(ERC6900TypesLib.packValidationHook(ERC6900TypesLib.pack(address(hook), 1)))
        );
        _install(true, hooks);

        // signature = ME ‖ [seg 0][len 2]["hk"] ‖ [0xFF][rawSig]; the hook reverts with what it saw.
        bytes memory sig =
            abi.encodePacked(ModuleEntity.unwrap(_me()), uint8(0), uint32(2), bytes("hk"), bytes1(0xff), hex"1234");
        vm.prank(signer);
        vm.expectRevert(abi.encodeWithSelector(MockSigHook.HookSaw.selector, RAW_HASH, signer, bytes("hk")));
        account.isValidSignature(RAW_HASH, sig);
    }
}
