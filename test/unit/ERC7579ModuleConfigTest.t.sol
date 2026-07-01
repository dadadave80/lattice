// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC7579ModuleConfig} from "@lattice/accounts/erc7579/ERC7579ModuleConfig.sol";
import {ERC7579ModuleConfigLib} from "@lattice/accounts/erc7579/libraries/ERC7579ModuleConfigLib.sol";
import {IModuleConfig} from "@lattice/interfaces/accounts/IModuleConfig.sol";
import {
    IERC7579Execution,
    IERC7579ModuleConfig,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_FALLBACK,
    MODULE_TYPE_HOOK,
    MODULE_TYPE_VALIDATOR
} from "@lattice/interfaces/external/IERC7579.sol";
import {Call} from "@lattice/interfaces/external/IERC7821.sol";
import {Test} from "forge-std/Test.sol";

contract MockAccount is AccessControl, ERC7579ModuleConfig {
    function initialize(address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ERC7579ModuleConfigLib.__ERC7579ModuleConfig_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

/// @dev A valid ERC-7579 executor module that can drive a batch on the account.
contract MockExecutor {
    bool public installed;
    bytes public lastInit;

    function onInstall(bytes calldata data) external {
        installed = true;
        lastInit = data;
    }

    function onUninstall(bytes calldata) external {
        installed = false;
    }

    function isModuleType(uint256 t) external pure returns (bool) {
        return t == MODULE_TYPE_EXECUTOR;
    }

    function drive(address account, bytes32 mode, bytes calldata execData) external returns (bytes[] memory) {
        return IERC7579Execution(account).executeFromExecutor(mode, execData);
    }
}

/// @dev A module that denies being an executor.
contract MockBadModule {
    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function isModuleType(uint256) external pure returns (bool) {
        return false;
    }
}

/// @dev A minimal ERC-7579 hook module (type 4).
contract MockHookModule {
    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function isModuleType(uint256 t) external pure returns (bool) {
        return t == MODULE_TYPE_HOOK;
    }

    function preCheck(address, uint256, bytes calldata) external pure returns (bytes memory) {
        return "";
    }

    function postCheck(bytes calldata) external {}
}

contract Target {
    uint256 public value;

    function setValue(uint256 v) external {
        value = v;
    }
}

contract ERC7579ModuleConfigTest is Test {
    MockAccount account;
    MockExecutor executor;
    Target target;
    address admin = address(0x1);

    bytes32 constant BATCH = 0x0100000000000000000000000000000000000000000000000000000000000000;

    function setUp() public {
        account = new MockAccount();
        account.initialize(admin);
        executor = new MockExecutor();
        target = new Target();
    }

    function _install(uint256 t, address module) internal {
        vm.prank(admin);
        account.installModule(t, module, "");
    }

    function _setValueData(uint256 v) internal view returns (bytes memory) {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(Target.setValue, (v))});
        return abi.encode(calls);
    }

    function test_AccountId() public view {
        assertEq(account.accountId(), "lattice.diamond-account.0.1.0", "accountId");
    }

    function test_SupportsModule() public view {
        assertTrue(account.supportsModule(MODULE_TYPE_EXECUTOR), "executor supported");
        assertTrue(account.supportsModule(MODULE_TYPE_VALIDATOR), "validator supported");
        assertTrue(account.supportsModule(MODULE_TYPE_HOOK), "hook supported");
        assertTrue(account.supportsModule(MODULE_TYPE_FALLBACK), "fallback supported");
        assertFalse(account.supportsModule(99), "unknown type unsupported");
    }

    function test_SupportsInterface() public view {
        assertTrue(account.supportsInterface(0x232dbb4a), "IERC7579ModuleConfig");
        assertTrue(account.supportsInterface(0xbe1d6cf6), "IERC7579AccountConfig");
        assertTrue(account.supportsInterface(0x3f3f9537), "IERC7579Execution");
    }

    function test_InstallModule() public {
        vm.expectEmit(false, false, false, true, address(account));
        emit IERC7579ModuleConfig.ModuleInstalled(MODULE_TYPE_EXECUTOR, address(executor));
        _install(MODULE_TYPE_EXECUTOR, address(executor));
        assertTrue(account.isModuleInstalled(MODULE_TYPE_EXECUTOR, address(executor), ""), "installed");
        assertTrue(executor.installed(), "onInstall called");
    }

    function test_InstallModule_AsSelf() public {
        vm.prank(address(account));
        account.installModule(MODULE_TYPE_EXECUTOR, address(executor), "");
        assertTrue(account.isModuleInstalled(MODULE_TYPE_EXECUTOR, address(executor), ""), "self install");
    }

    function test_InstallModule_RevertUnsupportedType() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IModuleConfig.UnsupportedModuleType.selector, uint256(99)));
        account.installModule(99, address(executor), "");
    }

    function test_InstallModule_RevertInvalidModule() public {
        MockBadModule bad = new MockBadModule();
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IModuleConfig.InvalidModuleForType.selector, address(bad), MODULE_TYPE_EXECUTOR)
        );
        account.installModule(MODULE_TYPE_EXECUTOR, address(bad), "");
    }

    function test_InstallModule_RevertAlreadyInstalled() public {
        _install(MODULE_TYPE_EXECUTOR, address(executor));
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModuleConfig.ModuleAlreadyInstalled.selector, MODULE_TYPE_EXECUTOR, address(executor)
            )
        );
        account.installModule(MODULE_TYPE_EXECUTOR, address(executor), "");
    }

    function test_InstallModule_RevertUnauthorized() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(IModuleConfig.UnauthorizedModuleConfig.selector, address(0xBAD)));
        account.installModule(MODULE_TYPE_EXECUTOR, address(executor), "");
    }

    function test_UninstallModule() public {
        _install(MODULE_TYPE_EXECUTOR, address(executor));
        vm.expectEmit(false, false, false, true, address(account));
        emit IERC7579ModuleConfig.ModuleUninstalled(MODULE_TYPE_EXECUTOR, address(executor));
        vm.prank(admin);
        account.uninstallModule(MODULE_TYPE_EXECUTOR, address(executor), "");
        assertFalse(account.isModuleInstalled(MODULE_TYPE_EXECUTOR, address(executor), ""), "uninstalled");
        assertFalse(executor.installed(), "onUninstall called");
    }

    function test_UninstallModule_RevertNotInstalled() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IModuleConfig.ModuleNotInstalled.selector, MODULE_TYPE_EXECUTOR, address(executor))
        );
        account.uninstallModule(MODULE_TYPE_EXECUTOR, address(executor), "");
    }

    function test_ExecuteFromExecutor() public {
        _install(MODULE_TYPE_EXECUTOR, address(executor));
        executor.drive(address(account), BATCH, _setValueData(99));
        assertEq(target.value(), 99, "executor batch not run");
    }

    function test_ExecuteFromExecutor_RevertNotInstalled() public {
        MockExecutor other = new MockExecutor(); // never installed
        vm.expectRevert(abi.encodeWithSelector(IModuleConfig.NotInstalledExecutor.selector, address(other)));
        other.drive(address(account), BATCH, _setValueData(1));
    }

    // ---- hook module (type 4) lifecycle ----

    function test_Hook_InstallAndUninstall() public {
        MockHookModule hook = new MockHookModule();
        vm.prank(admin);
        account.installModule(MODULE_TYPE_HOOK, address(hook), "");
        assertTrue(account.isModuleInstalled(MODULE_TYPE_HOOK, address(hook), ""), "hook not installed");
        vm.prank(admin);
        account.uninstallModule(MODULE_TYPE_HOOK, address(hook), "");
        assertFalse(account.isModuleInstalled(MODULE_TYPE_HOOK, address(hook), ""), "hook not uninstalled");
    }

    /// @dev Only one global hook; a second install reverts until the first is uninstalled.
    function test_Hook_OnlyOneGlobalHook() public {
        MockHookModule h1 = new MockHookModule();
        MockHookModule h2 = new MockHookModule();
        vm.prank(admin);
        account.installModule(MODULE_TYPE_HOOK, address(h1), "");

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IModuleConfig.ModuleAlreadyInstalled.selector, MODULE_TYPE_HOOK, address(h1))
        );
        account.installModule(MODULE_TYPE_HOOK, address(h2), "");

        vm.prank(admin);
        account.uninstallModule(MODULE_TYPE_HOOK, address(h1), "");
        vm.prank(admin);
        account.installModule(MODULE_TYPE_HOOK, address(h2), ""); // now succeeds
        assertTrue(account.isModuleInstalled(MODULE_TYPE_HOOK, address(h2), ""), "h2 not installed after swap");
    }
}
