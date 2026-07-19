// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC6900ModuleManager} from "@lattice/accounts/erc6900/ERC6900ModuleManager.sol";
import {ERC6900ModuleManagerLib} from "@lattice/accounts/erc6900/libraries/ERC6900ModuleManagerLib.sol";
import {ERC6900TypesLib} from "@lattice/accounts/erc6900/libraries/ERC6900TypesLib.sol";
import {IERC6900ModuleManager} from "@lattice/interfaces/accounts/IERC6900ModuleManager.sol";
import {
    HookConfig,
    IERC6900Account,
    MAX_VALIDATION_ASSOC_HOOKS,
    ModuleEntity,
    ValidationConfig,
    ValidationDataView,
    ValidationFlags
} from "@lattice/interfaces/external/ercs/IERC6900.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Minimal ERC-6900 module that records its uninstall and can revert in onUninstall (for swallow tests).
contract MockValModule {
    bytes public lastInstall;
    bool public uninstalled;
    bool public revertOnUninstall;

    function setRevertOnUninstall(bool v) external {
        revertOnUninstall = v;
    }

    function onInstall(bytes calldata data) external {
        lastInstall = data;
    }

    function onUninstall(bytes calldata) external {
        if (revertOnUninstall) revert("uninstall failed");
        uninstalled = true;
    }

    function moduleId() external pure returns (string memory) {
        return "lattice.mockval.1.0.0";
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

contract MockValManager is ERC6900ModuleManager, AccessControl {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(ERC6900ModuleManager, AccessControl)
        returns (bytes memory)
    {}

    function initialize(address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        InitializableLib.postInitializer(s);
    }

    function getValidationData(ModuleEntity v) external view returns (ValidationDataView memory) {
        return ERC6900ModuleManagerLib.getValidationData(v);
    }
}

contract ERC6900ModuleManagerValidationTest is Test {
    MockValManager mgr;
    MockValModule module;
    address admin = address(0xA11CE);

    uint32 constant ENTITY = 7;
    bytes4 constant SEL_A = 0xaaaaaaaa;
    bytes4 constant SEL_B = 0xbbbbbbbb;

    function setUp() public {
        module = new MockValModule();
        mgr = new MockValManager();
        mgr.initialize(admin);
    }

    // ---- helpers ----

    function _me() internal view returns (ModuleEntity) {
        return ERC6900TypesLib.pack(address(module), ENTITY);
    }

    function _config(bool global, bool sig, bool userOp) internal view returns (ValidationConfig) {
        return ERC6900TypesLib.pack(address(module), ENTITY, global, sig, userOp);
    }

    function _valHook(address hookModule, uint32 entityId, bytes memory data) internal pure returns (bytes memory) {
        HookConfig hc = ERC6900TypesLib.packValidationHook(ERC6900TypesLib.pack(hookModule, entityId));
        return abi.encodePacked(HookConfig.unwrap(hc), data);
    }

    function _execHook(address hookModule, uint32 entityId, bool pre, bool post, bytes memory data)
        internal
        pure
        returns (bytes memory)
    {
        HookConfig hc = ERC6900TypesLib.packExecHook(ERC6900TypesLib.pack(hookModule, entityId), pre, post);
        return abi.encodePacked(HookConfig.unwrap(hc), data);
    }

    function _sels(bytes4 a) internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = a;
    }

    function _install(ValidationConfig cfg, bytes4[] memory selectors, bytes memory installData, bytes[] memory hooks)
        internal
    {
        vm.prank(admin);
        mgr.installValidation(cfg, selectors, installData, hooks);
    }

    function _containsHook(HookConfig[] memory arr, HookConfig h) internal pure returns (bool) {
        for (uint256 i; i < arr.length; ++i) {
            if (HookConfig.unwrap(arr[i]) == HookConfig.unwrap(h)) return true;
        }
        return false;
    }

    function _containsSel(bytes4[] memory arr, bytes4 s) internal pure returns (bool) {
        for (uint256 i; i < arr.length; ++i) {
            if (arr[i] == s) return true;
        }
        return false;
    }

    // ---- install ----

    function test_InstallValidation_StoresFlagsAndSelectors() public {
        bytes4[] memory s = new bytes4[](2);
        (s[0], s[1]) = (SEL_A, SEL_B);
        _install(_config(true, false, true), s, "", new bytes[](0));
        ValidationDataView memory d = mgr.getValidationData(_me());
        assertEq(ValidationFlags.unwrap(d.validationFlags), 0x05, "flags = isGlobal|isUserOp");
        assertTrue(_containsSel(d.selectors, SEL_A) && _containsSel(d.selectors, SEL_B), "selectors stored");
    }

    function test_InstallValidation_StoresValidationHook() public {
        bytes[] memory hooks = new bytes[](1);
        hooks[0] = _valHook(address(module), 1, "");
        _install(_config(false, false, true), _sels(SEL_A), "", hooks);
        HookConfig expected = ERC6900TypesLib.packValidationHook(ERC6900TypesLib.pack(address(module), 1));
        assertTrue(_containsHook(mgr.getValidationData(_me()).validationHooks, expected), "validation hook stored");
    }

    function test_InstallValidation_StoresExecHook() public {
        bytes[] memory hooks = new bytes[](1);
        hooks[0] = _execHook(address(module), 2, true, false, "");
        _install(_config(false, false, true), _sels(SEL_A), "", hooks);
        HookConfig expected = ERC6900TypesLib.packExecHook(ERC6900TypesLib.pack(address(module), 2), true, false);
        assertTrue(_containsHook(mgr.getValidationData(_me()).executionHooks, expected), "exec hook stored");
    }

    function test_InstallValidation_CallsModuleOnInstall() public {
        _install(_config(true, false, false), _sels(SEL_A), hex"beef", new bytes[](0));
        assertEq(module.lastInstall(), hex"beef", "module onInstall data");
    }

    function test_InstallValidation_CallsHookOnInstall() public {
        MockValModule hook = new MockValModule();
        bytes[] memory hooks = new bytes[](1);
        hooks[0] = _valHook(address(hook), 1, hex"cafe");
        _install(_config(false, false, true), _sels(SEL_A), "", hooks);
        assertEq(hook.lastInstall(), hex"cafe", "hook onInstall data");
    }

    function test_InstallValidation_AllowsDuplicateValidationHook() public {
        bytes[] memory hooks = new bytes[](2);
        hooks[0] = _valHook(address(module), 1, "");
        hooks[1] = _valHook(address(module), 1, ""); // identical — duplicates ALLOWED in the ordered array
        _install(_config(false, false, true), _sels(SEL_A), "", hooks);
        assertEq(mgr.getValidationData(_me()).validationHooks.length, 2, "both stored");
    }

    function test_InstallValidation_OverwritesFlags() public {
        _install(_config(true, true, true), _sels(SEL_A), "", new bytes[](0));
        _install(_config(false, false, true), _sels(SEL_B), "", new bytes[](0)); // re-install overwrites flags
        assertEq(ValidationFlags.unwrap(mgr.getValidationData(_me()).validationFlags), 0x01, "flags overwritten");
    }

    function test_InstallValidation_RevertDuplicateSelector() public {
        bytes4[] memory s = new bytes4[](2);
        (s[0], s[1]) = (SEL_A, SEL_A);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IERC6900ModuleManager.ValidationAlreadySet.selector, SEL_A, _me()));
        mgr.installValidation(_config(true, false, true), s, "", new bytes[](0));
    }

    function test_InstallValidation_RevertDuplicateExecHook() public {
        bytes[] memory hooks = new bytes[](2);
        hooks[0] = _execHook(address(module), 2, true, false, "");
        hooks[1] = _execHook(address(module), 2, true, false, ""); // identical exec hook — set dedupes/reverts
        HookConfig dup = ERC6900TypesLib.packExecHook(ERC6900TypesLib.pack(address(module), 2), true, false);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IERC6900ModuleManager.ExecutionHookAlreadySet.selector, dup));
        mgr.installValidation(_config(false, false, true), _sels(SEL_A), "", hooks);
    }

    function test_InstallValidation_RevertHookLimitExceeded() public {
        // 256 validation hooks: the 256th push makes length 256 > MAX (255) and reverts. Empty hookData => no calls.
        bytes[] memory hooks = new bytes[](uint256(MAX_VALIDATION_ASSOC_HOOKS) + 1);
        for (uint256 i; i < hooks.length; ++i) {
            hooks[i] = _valHook(address(module), uint32(i), "");
        }
        vm.prank(admin);
        vm.expectRevert(IERC6900ModuleManager.PreValidationHookLimitExceeded.selector);
        mgr.installValidation(_config(false, false, true), _sels(SEL_A), "", hooks);
    }

    function test_InstallValidation_RevertUnauthorized() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(IERC6900ModuleManager.UnauthorizedModuleConfig.selector, address(0xBAD)));
        mgr.installValidation(_config(true, false, true), _sels(SEL_A), "", new bytes[](0));
    }

    // ---- uninstall ----

    function test_UninstallValidation_ClearsState() public {
        bytes[] memory hooks = new bytes[](1);
        hooks[0] = _valHook(address(module), 1, "");
        _install(_config(true, false, true), _sels(SEL_A), "", hooks);

        vm.prank(admin);
        mgr.uninstallValidation(_me(), "", new bytes[](0));

        ValidationDataView memory d = mgr.getValidationData(_me());
        assertEq(ValidationFlags.unwrap(d.validationFlags), 0, "flags cleared");
        assertEq(d.selectors.length, 0, "selectors cleared");
        assertEq(d.validationHooks.length, 0, "validation hooks cleared");
    }

    function test_UninstallValidation_CallsModuleOnUninstall() public {
        _install(_config(true, false, true), _sels(SEL_A), "", new bytes[](0));
        vm.prank(admin);
        mgr.uninstallValidation(_me(), hex"01", new bytes[](0));
        assertTrue(module.uninstalled(), "module onUninstall ran");
    }

    function test_UninstallValidation_CallsHookOnUninstall() public {
        MockValModule vHook = new MockValModule();
        MockValModule eHook = new MockValModule();
        bytes[] memory hooks = new bytes[](2);
        hooks[0] = _valHook(address(vHook), 1, "");
        hooks[1] = _execHook(address(eHook), 2, true, false, "");
        _install(_config(false, false, true), _sels(SEL_A), "", hooks);

        bytes[] memory hookUninstall = new bytes[](2);
        hookUninstall[0] = hex"01"; // validation hook first
        hookUninstall[1] = hex"01"; // exec hook second
        vm.prank(admin);
        mgr.uninstallValidation(_me(), "", hookUninstall);

        assertTrue(vHook.uninstalled(), "validation hook onUninstall ran");
        assertTrue(eHook.uninstalled(), "exec hook onUninstall ran");
    }

    function test_UninstallValidation_RevertArrayLengthMismatch() public {
        bytes[] memory hooks = new bytes[](1);
        hooks[0] = _valHook(address(module), 1, "");
        _install(_config(false, false, true), _sels(SEL_A), "", hooks);

        bytes[] memory wrong = new bytes[](2); // total installed hooks == 1
        vm.prank(admin);
        vm.expectRevert(IERC6900ModuleManager.ArrayLengthMismatch.selector);
        mgr.uninstallValidation(_me(), "", wrong);
    }

    function test_UninstallValidation_EmptyHookDataClearsButSkipsCallbacks() public {
        bytes[] memory hooks = new bytes[](1);
        hooks[0] = _valHook(address(module), 1, "");
        _install(_config(false, false, true), _sels(SEL_A), "", hooks);
        module.setRevertOnUninstall(true); // would revert IF called

        vm.prank(admin);
        mgr.uninstallValidation(_me(), "", new bytes[](0)); // empty => no callbacks, still clears

        assertEq(mgr.getValidationData(_me()).validationHooks.length, 0, "hooks cleared");
        assertFalse(module.uninstalled(), "hook onUninstall not called");
    }

    function test_UninstallValidation_SwallowsHookRevertIntoEvent() public {
        MockValModule vHook = new MockValModule();
        vHook.setRevertOnUninstall(true);
        bytes[] memory hooks = new bytes[](1);
        hooks[0] = _valHook(address(vHook), 1, "");
        _install(_config(false, false, true), _sels(SEL_A), "", hooks);

        bytes[] memory hookUninstall = new bytes[](1);
        hookUninstall[0] = hex"01";
        // Reverting hook onUninstall must be swallowed; event reports onUninstallSucceeded = false.
        vm.expectEmit(true, true, false, true, address(mgr));
        emit IERC6900Account.ValidationUninstalled(address(module), ENTITY, false);
        vm.prank(admin);
        mgr.uninstallValidation(_me(), "", hookUninstall);
    }
}
