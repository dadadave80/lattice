// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC6900ModuleManager} from "@lattice/accounts/erc6900/ERC6900ModuleManager.sol";
import {ERC6900Validation} from "@lattice/accounts/erc6900/ERC6900Validation.sol";
import {ERC6900TypesLib} from "@lattice/accounts/erc6900/libraries/ERC6900TypesLib.sol";
import {ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {IERC6900Executor} from "@lattice/interfaces/accounts/IERC6900Executor.sol";
import {IERC6900Validation} from "@lattice/interfaces/accounts/IERC6900Validation.sol";
import {PackedUserOperation} from "@lattice/interfaces/external/ercs/IAccount.sol";
import {
    HookConfig,
    IERC6900Account,
    ModuleEntity,
    ValidationConfig
} from "@lattice/interfaces/external/ercs/IERC6900.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

/// @dev A minimal ERC-6900 user-op validation module: records the call and returns a configurable validationData.
contract MockUserOpValidation {
    bool public called;
    uint256 public retData;

    function setRet(uint256 r) external {
        retData = r;
    }

    function validateUserOp(uint32, PackedUserOperation calldata, bytes32) external returns (uint256) {
        called = true;
        return retData;
    }

    function preUserOpValidationHook(uint32, PackedUserOperation calldata, bytes32) external pure returns (uint256) {
        return 0;
    }

    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function moduleId() external pure returns (string memory) {
        return "lattice.mockuserop.1.0.0";
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

/// @dev A pre-userOp-validation hook module: records the signature segment it received and returns a settable
///      packed validationData.
contract MockUserOpHook {
    uint256 public ret;
    bytes public lastSig;

    function setRet(uint256 r) external {
        ret = r;
    }

    function preUserOpValidationHook(uint32, PackedUserOperation calldata op, bytes32) external returns (uint256) {
        lastSig = op.signature;
        return ret;
    }

    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function moduleId() external pure returns (string memory) {
        return "lattice.mockhook.1.0.0";
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

contract MockValAccount is AccessControl, ERC6900ModuleManager, ERC6900Validation, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, ERC6900ModuleManager, ERC6900Validation)
        returns (bytes memory)
    {}

    function initialize(address admin_, address entryPoint_) external initializer {
        AccessControlLib.__AccessControl_init(admin_);
        ERC4337ValidationLib.__ERC4337Validation_init(entryPoint_);
    }
}

contract ERC6900ValidationUserOpTest is Test {
    MockValAccount account;
    MockUserOpValidation val;
    address admin = address(0xA11CE);
    address entryPoint = address(0xE417401);

    uint32 constant ENTITY = 5;

    function setUp() public {
        account = new MockValAccount();
        account.initialize(admin, entryPoint);
        val = new MockUserOpValidation();
    }

    function _me() internal view returns (ModuleEntity) {
        return ERC6900TypesLib.pack(address(val), ENTITY);
    }

    function _install(bool global, bool isUserOp, bytes4[] memory sels) internal {
        ValidationConfig cfg = ERC6900TypesLib.pack(address(val), ENTITY, global, false, isUserOp);
        vm.prank(admin);
        account.installValidation(cfg, sels, "", new bytes[](0));
    }

    function _sel(bytes4 a) internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = a;
    }

    /// @dev signature = ModuleEntity(24) ‖ globalFlag(1) ‖ 0xFF final-segment marker ‖ rawSig.
    function _op(bool global, bytes memory rawSig) internal view returns (PackedUserOperation memory op) {
        op.sender = address(account);
        op.callData = abi.encodeCall(IERC6900Account.execute, (address(0xBEEF), 0, ""));
        op.signature =
            abi.encodePacked(ModuleEntity.unwrap(_me()), global ? bytes1(0x01) : bytes1(0x00), bytes1(0xff), rawSig);
    }

    function _validate(PackedUserOperation memory op, uint256 funds) internal returns (uint256) {
        vm.prank(entryPoint);
        return account.validateUserOp(op, bytes32(uint256(1)), funds);
    }

    // ---- routing ----

    function test_ValidateUserOp_GlobalRoutesToValidation() public {
        _install(true, true, new bytes4[](0)); // global, isUserOpValidation
        uint256 vd = _validate(_op(true, ""), 0);
        assertTrue(val.called(), "module validateUserOp called");
        assertEq(vd, 0, "success");
    }

    function test_ValidateUserOp_SelectorRoutesToValidation() public {
        _install(false, true, _sel(IERC6900Account.execute.selector)); // selector-scoped to execute
        uint256 vd = _validate(_op(false, ""), 0);
        assertTrue(val.called(), "module called via selector path");
        assertEq(vd, 0, "success");
    }

    function test_ValidateUserOp_SigFailurePassesThrough() public {
        _install(true, true, new bytes4[](0));
        val.setRet(1); // SIG_VALIDATION_FAILED
        assertEq(_validate(_op(true, ""), 0), 1, "failure surfaced, not reverted");
    }

    function test_ValidateUserOp_PaysPrefund() public {
        _install(true, true, new bytes4[](0));
        vm.deal(address(account), 1 ether);
        uint256 before = entryPoint.balance;
        _validate(_op(true, ""), 0.4 ether);
        assertEq(entryPoint.balance - before, 0.4 ether, "prefund paid to EntryPoint");
    }

    // ---- reverts ----

    function test_ValidateUserOp_RevertNotFromEntryPoint() public {
        _install(true, true, new bytes4[](0));
        PackedUserOperation memory op = _op(true, "");
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(IERC6900Validation.NotFromEntryPoint.selector, address(0xBAD)));
        account.validateUserOp(op, bytes32(uint256(1)), 0);
    }

    function test_ValidateUserOp_RevertNotApplicable() public {
        _install(false, true, new bytes4[](0)); // not global, no selectors → cannot validate execute
        PackedUserOperation memory op = _op(false, "");
        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC6900Executor.ValidationFunctionMissing.selector, IERC6900Account.execute.selector
            )
        );
        account.validateUserOp(op, bytes32(uint256(1)), 0);
    }

    function test_ValidateUserOp_RevertNotUserOpFlag() public {
        _install(true, false, new bytes4[](0)); // global but NOT isUserOpValidation
        PackedUserOperation memory op = _op(true, "");
        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(IERC6900Validation.UserOpValidationInvalid.selector, address(val), ENTITY)
        );
        account.validateUserOp(op, bytes32(uint256(1)), 0);
    }

    // ---- pre-userOp-validation hooks ----

    MockUserOpHook hook;

    /// @dev Installs a global isUserOpValidation `val` with one pre-userOp-validation hook (entityId 1).
    function _installWithHook() internal returns (MockUserOpHook) {
        hook = new MockUserOpHook();
        bytes[] memory hooks = new bytes[](1);
        HookConfig hc = ERC6900TypesLib.packValidationHook(ERC6900TypesLib.pack(address(hook), 1));
        hooks[0] = abi.encodePacked(HookConfig.unwrap(hc));
        ValidationConfig cfg = ERC6900TypesLib.pack(address(val), ENTITY, true, false, true);
        vm.prank(admin);
        account.installValidation(cfg, new bytes4[](0), "", hooks);
        return hook;
    }

    /// @dev signature = ME ‖ globalFlag ‖ [seg index 0][len][hookSig] ‖ [0xFF final][mainSig].
    function _opWithHookSig(bytes memory hookSig, bytes memory mainSig)
        internal
        view
        returns (PackedUserOperation memory op)
    {
        op.sender = address(account);
        op.callData = abi.encodeCall(IERC6900Account.execute, (address(0xBEEF), 0, ""));
        op.signature = abi.encodePacked(
            ModuleEntity.unwrap(_me()), bytes1(0x01), uint8(0), uint32(hookSig.length), hookSig, bytes1(0xff), mainSig
        );
    }

    function test_ValidateUserOp_RunsPreValidationHook() public {
        _installWithHook();
        _validate(_opWithHookSig("hooksig", ""), 0);
        assertTrue(val.called(), "validation ran");
        assertEq(hook.lastSig(), bytes("hooksig"), "hook received its signature segment");
    }

    function test_ValidateUserOp_HookFailureVetoes() public {
        _installWithHook();
        hook.setRet(1); // SIG_VALIDATION_FAILED from the hook
        val.setRet(0); // validation function succeeds
        // hook needs no signature data → its segment is OMITTED (signature jumps to the 0xFF final segment).
        uint256 vd = _validate(_op(true, ""), 0);
        assertEq(uint160(vd), 1, "failing hook vetoes the authorizer");
    }

    function test_ValidateUserOp_RevertUnexpectedAggregator() public {
        _installWithHook();
        hook.setRet(uint256(uint160(address(2)))); // authorizer > 1 (an aggregator) is forbidden for hooks
        PackedUserOperation memory op = _op(true, "");
        vm.prank(entryPoint);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC6900Validation.UnexpectedAggregator.selector, address(hook), uint32(1), address(2)
            )
        );
        account.validateUserOp(op, bytes32(uint256(1)), 0);
    }

    function test_ValidateUserOp_TimeRangeIntersects() public {
        _installWithHook();
        hook.setRet(uint256(100) << 160); // hook validUntil = 100
        val.setRet(uint256(200) << 160); // validation validUntil = 200
        uint256 vd = _validate(_op(true, ""), 0);
        assertEq(uint48(vd >> 160), 100, "validUntil = min(100, 200)");
    }

    function test_ValidateUserOp_RejectsExecHookValidation() public {
        // A validation carrying an execution hook needs the executeUserOp wrapper (unsupported) → reject.
        MockUserOpHook eHook = new MockUserOpHook();
        bytes[] memory hooks = new bytes[](1);
        HookConfig hc = ERC6900TypesLib.packExecHook(ERC6900TypesLib.pack(address(eHook), 2), true, false);
        hooks[0] = abi.encodePacked(HookConfig.unwrap(hc));
        ValidationConfig cfg = ERC6900TypesLib.pack(address(val), ENTITY, true, false, true);
        vm.prank(admin);
        account.installValidation(cfg, new bytes4[](0), "", hooks);

        PackedUserOperation memory op = _op(true, "");
        vm.prank(entryPoint);
        vm.expectRevert(IERC6900Validation.RequireUserOperationContext.selector);
        account.validateUserOp(op, bytes32(uint256(1)), 0);
    }
}
