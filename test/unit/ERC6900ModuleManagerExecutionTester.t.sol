// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC6900ModuleManager} from "@lattice/accounts/ERC6900ModuleManager.sol";
import {ERC6900ModuleManagerLib} from "@lattice/accounts/libraries/ERC6900ModuleManagerLib.sol";
import {ERC6900TypesLib} from "@lattice/accounts/libraries/ERC6900TypesLib.sol";
import {IModuleManager6900} from "@lattice/interfaces/IModuleManager6900.sol";
import {
    ExecutionDataView,
    ExecutionManifest,
    HookConfig,
    IERC6900Account,
    ManifestExecutionFunction,
    ManifestExecutionHook,
    ModuleEntity
} from "@lattice/interfaces/external/IERC6900.sol";
import {Test} from "forge-std/Test.sol";

/// @dev A facet cut into the mock so the diamond facet map owns `facetPing()` (for the shadow-guard case).
contract DummyFacet {
    function facetPing() external pure returns (uint256) {
        return 7;
    }
}

/// @dev A minimal ERC-6900 module: records its install data and can be told to revert in either callback.
contract MockModule {
    bytes public lastInstall;
    bool public uninstalled;
    bool public revertOnInstall;
    bool public revertOnUninstall;

    function setRevertOnInstall(bool v) external {
        revertOnInstall = v;
    }

    function setRevertOnUninstall(bool v) external {
        revertOnUninstall = v;
    }

    function onInstall(bytes calldata data) external {
        if (revertOnInstall) revert("install failed");
        lastInstall = data;
    }

    function onUninstall(bytes calldata) external {
        if (revertOnUninstall) revert("uninstall failed");
        uninstalled = true;
    }

    function moduleId() external pure returns (string memory) {
        return "lattice.mock.1.0.0";
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

contract MockManager is ERC6900ModuleManager, AccessControl {
    function initialize(address admin_, FacetCut[] calldata cuts) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        DiamondLib.diamondCut(cuts, address(0), msg.data[0:0]);
        InitializableLib.postInitializer(s);
    }

    function getExecutionData(bytes4 selector) external view returns (ExecutionDataView memory) {
        return ERC6900ModuleManagerLib.getExecutionData(selector);
    }

    function interfaceRefCount(bytes4 id) external view returns (uint256) {
        return ERC6900ModuleManagerLib.interfaceRefCount(id);
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }

    /// @dev Simulates a natively-registered ERC-165 bit (e.g. ERC165/loupe/IERC7579*) — set true with no module
    ///      reference, as the Diamond core / sibling facets do via direct sstore.
    function setNativeInterface(bytes4 id) external {
        ERC165Lib.erc165Storage().supportedInterfaces[id] = true;
    }
}

contract ERC6900ModuleManagerExecutionTester is Test {
    MockManager mgr;
    MockModule module;
    DummyFacet dummy;
    address admin = address(0xA11CE);

    bytes4 constant EXEC_SEL = 0x12345678;
    bytes4 constant IFACE_ID = 0xdeadbeef;

    function setUp() public {
        dummy = new DummyFacet();
        module = new MockModule();
        mgr = new MockManager();

        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DummyFacet.facetPing.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Add, functionSelectors: sels});
        mgr.initialize(admin, cuts);
    }

    // ---- manifest builders ----

    function _fn(bytes4 selector) internal pure returns (ManifestExecutionFunction memory) {
        return ManifestExecutionFunction({
            executionSelector: selector, skipRuntimeValidation: true, allowGlobalValidation: true
        });
    }

    function _manifest(bytes4 selector) internal pure returns (ExecutionManifest memory m) {
        m.executionFunctions = new ManifestExecutionFunction[](1);
        m.executionFunctions[0] = _fn(selector);
    }

    function _manifestWithHook(bytes4 selector, uint32 entityId, bool pre, bool post)
        internal
        pure
        returns (ExecutionManifest memory m)
    {
        m = _manifest(selector);
        m.executionHooks = new ManifestExecutionHook[](1);
        m.executionHooks[0] =
            ManifestExecutionHook({executionSelector: selector, entityId: entityId, isPreHook: pre, isPostHook: post});
    }

    function _manifestWithIface(bytes4 selector, bytes4 ifaceId) internal pure returns (ExecutionManifest memory m) {
        m = _manifest(selector);
        m.interfaceIds = new bytes4[](1);
        m.interfaceIds[0] = ifaceId;
    }

    function _install(ExecutionManifest memory m, bytes memory data) internal {
        vm.prank(admin);
        mgr.installExecution(address(module), m, data);
    }

    function _containsHook(HookConfig[] memory arr, HookConfig h) internal pure returns (bool) {
        for (uint256 i; i < arr.length; ++i) {
            if (HookConfig.unwrap(arr[i]) == HookConfig.unwrap(h)) return true;
        }
        return false;
    }

    // ---- install ----

    function test_InstallExecution_RegistersFunction() public {
        _install(_manifest(EXEC_SEL), "");
        ExecutionDataView memory d = mgr.getExecutionData(EXEC_SEL);
        assertEq(d.module, address(module), "module");
        assertTrue(d.skipRuntimeValidation, "skipRuntimeValidation");
        assertTrue(d.allowGlobalValidation, "allowGlobalValidation");
    }

    function test_InstallExecution_RegistersExecHooks() public {
        _install(_manifestWithHook(EXEC_SEL, 9, true, true), "");
        HookConfig expected = ERC6900TypesLib.packExecHook(ERC6900TypesLib.pack(address(module), 9), true, true);
        assertTrue(_containsHook(mgr.getExecutionData(EXEC_SEL).executionHooks, expected), "exec hook stored");
    }

    function test_InstallExecution_AddsInterfaceId() public {
        _install(_manifestWithIface(EXEC_SEL, IFACE_ID), "");
        assertEq(mgr.interfaceRefCount(IFACE_ID), 1, "refcount");
        assertTrue(mgr.supportsInterface(IFACE_ID), "ERC165 advertised");
    }

    function test_InstallExecution_CallsOnInstall() public {
        _install(_manifest(EXEC_SEL), hex"c0ffee");
        assertEq(module.lastInstall(), hex"c0ffee", "onInstall data");
    }

    function test_InstallExecution_OnInstallDataGated() public {
        // Empty installData => onInstall is NOT called, so even a would-revert module installs cleanly.
        module.setRevertOnInstall(true);
        _install(_manifest(EXEC_SEL), "");
        assertEq(mgr.getExecutionData(EXEC_SEL).module, address(module), "installed without calling onInstall");
    }

    function test_InstallExecution_RevertNullModule() public {
        vm.prank(admin);
        vm.expectRevert(IModuleManager6900.NullModule.selector);
        mgr.installExecution(address(0), _manifest(EXEC_SEL), "");
    }

    function test_InstallExecution_RevertAlreadySet() public {
        _install(_manifest(EXEC_SEL), "");
        MockModule other = new MockModule();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IModuleManager6900.ExecutionFunctionAlreadySet.selector, EXEC_SEL));
        mgr.installExecution(address(other), _manifest(EXEC_SEL), "");
    }

    function test_InstallExecution_RevertShadowsFacet() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModuleManager6900.ExecutionFunctionShadowsFacet.selector, DummyFacet.facetPing.selector
            )
        );
        mgr.installExecution(address(module), _manifest(DummyFacet.facetPing.selector), "");
    }

    function test_InstallExecution_RevertExecHookAlreadySet() public {
        ExecutionManifest memory m = _manifest(EXEC_SEL);
        m.executionHooks = new ManifestExecutionHook[](2);
        m.executionHooks[0] =
            ManifestExecutionHook({executionSelector: EXEC_SEL, entityId: 1, isPreHook: true, isPostHook: false});
        m.executionHooks[1] = m.executionHooks[0]; // exact duplicate
        HookConfig dup = ERC6900TypesLib.packExecHook(ERC6900TypesLib.pack(address(module), 1), true, false);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IModuleManager6900.ExecutionHookAlreadySet.selector, dup));
        mgr.installExecution(address(module), m, "");
    }

    function test_InstallExecution_RevertUnauthorized() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(IModuleManager6900.UnauthorizedModuleConfig.selector, address(0xBAD)));
        mgr.installExecution(address(module), _manifest(EXEC_SEL), "");
    }

    function test_InstallExecution_RevertOnInstallFailure() public {
        module.setRevertOnInstall(true);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModuleManager6900.ModuleInstallCallbackFailed.selector,
                address(module),
                abi.encodeWithSignature("Error(string)", "install failed")
            )
        );
        mgr.installExecution(address(module), _manifest(EXEC_SEL), hex"01");
    }

    function test_InstallExecution_RevertInterfaceIdSentinel() public {
        // ERC-165 requires supportsInterface(0xffffffff) == false; a manifest may not refcount it true.
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IModuleManager6900.InvalidInterfaceId.selector, bytes4(0xffffffff)));
        mgr.installExecution(address(module), _manifestWithIface(EXEC_SEL, 0xffffffff), "");
    }

    function test_InstallExecution_RevertNativeInterfaceIdCollision() public {
        // A natively-supported id (bit true, refcount 0) may not be refcounted by a module — else a later
        // uninstall would clear the native bit and desync the ERC-165 view.
        bytes4 nativeId = 0x01ffc9a7; // type(IERC165).interfaceId
        mgr.setNativeInterface(nativeId);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IModuleManager6900.InvalidInterfaceId.selector, nativeId));
        mgr.installExecution(address(module), _manifestWithIface(EXEC_SEL, nativeId), "");
        assertTrue(mgr.supportsInterface(nativeId), "native bit untouched");
    }

    // ---- uninstall ----

    function test_UninstallExecution_RemovesFunction() public {
        _install(_manifest(EXEC_SEL), "");
        vm.prank(admin);
        mgr.uninstallExecution(address(module), _manifest(EXEC_SEL), "");
        assertEq(mgr.getExecutionData(EXEC_SEL).module, address(0), "removed");
    }

    function test_UninstallExecution_RemovesExecHooks() public {
        ExecutionManifest memory m = _manifestWithHook(EXEC_SEL, 9, true, true);
        _install(m, "");
        vm.prank(admin);
        mgr.uninstallExecution(address(module), m, "");
        assertEq(mgr.getExecutionData(EXEC_SEL).executionHooks.length, 0, "hooks removed");
    }

    function test_UninstallExecution_DecrementsInterfaceId() public {
        ExecutionManifest memory m = _manifestWithIface(EXEC_SEL, IFACE_ID);
        _install(m, "");
        vm.prank(admin);
        mgr.uninstallExecution(address(module), m, "");
        assertEq(mgr.interfaceRefCount(IFACE_ID), 0, "refcount cleared");
        assertFalse(mgr.supportsInterface(IFACE_ID), "ERC165 retracted");
    }

    function test_UninstallExecution_OnUninstallSucceeded() public {
        ExecutionManifest memory m = _manifest(EXEC_SEL);
        _install(m, "");
        vm.expectEmit(true, false, false, true, address(mgr));
        emit IERC6900Account.ExecutionUninstalled(address(module), true, m);
        vm.prank(admin);
        mgr.uninstallExecution(address(module), m, hex"01");
        assertTrue(module.uninstalled(), "onUninstall ran");
    }

    function test_UninstallExecution_SwallowsOnUninstallRevert() public {
        ExecutionManifest memory m = _manifest(EXEC_SEL);
        _install(m, "");
        module.setRevertOnUninstall(true);
        // Reverting onUninstall must NOT revert the uninstall; state is still removed.
        vm.expectEmit(true, false, false, true, address(mgr));
        emit IERC6900Account.ExecutionUninstalled(address(module), false, m);
        vm.prank(admin);
        mgr.uninstallExecution(address(module), m, hex"01");
        assertEq(mgr.getExecutionData(EXEC_SEL).module, address(0), "still removed");
        assertFalse(module.uninstalled(), "revert path did not set flag");
    }
}
