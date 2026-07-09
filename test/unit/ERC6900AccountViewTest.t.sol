// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC6900AccountView} from "@lattice/accounts/erc6900/ERC6900AccountView.sol";
import {ERC6900ModuleManager} from "@lattice/accounts/erc6900/ERC6900ModuleManager.sol";
import {ERC6900TypesLib} from "@lattice/accounts/erc6900/libraries/ERC6900TypesLib.sol";
import {
    ExecutionDataView,
    ExecutionManifest,
    HookConfig,
    IERC6900Account,
    ManifestExecutionFunction,
    ManifestExecutionHook,
    ModuleEntity,
    ValidationConfig,
    ValidationDataView,
    ValidationFlags
} from "@lattice/interfaces/external/IERC6900.sol";
import {Test} from "forge-std/Test.sol";

contract DummyFacet {
    function facetPing() external pure returns (uint256) {
        return 7;
    }
}

contract MockModule {
    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function moduleId() external pure returns (string memory) {
        return "lattice.mock.1.0.0";
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

contract MockViewAccount is AccessControl, ERC6900ModuleManager, ERC6900AccountView {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, ERC6900ModuleManager, ERC6900AccountView)
        returns (bytes memory)
    {}

    function initialize(address admin_, FacetCut[] calldata cuts) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        DiamondLib.diamondCut(cuts, address(0), msg.data[0:0]);
        InitializableLib.postInitializer(s);
    }
}

contract ERC6900AccountViewTest is Test {
    MockViewAccount account;
    MockModule module;
    DummyFacet dummy;
    address admin = address(0xA11CE);

    bytes4 constant EXEC_SEL = 0x12345678;
    uint32 constant ENTITY = 5;

    function setUp() public {
        dummy = new DummyFacet();
        module = new MockModule();
        account = new MockViewAccount();

        // Cut facetPing + execute/executeBatch selectors (the latter two are "native validation-gated").
        bytes4[] memory sels = new bytes4[](3);
        sels[0] = DummyFacet.facetPing.selector;
        sels[1] = IERC6900Account.execute.selector;
        sels[2] = IERC6900Account.executeBatch.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Add, functionSelectors: sels});
        account.initialize(admin, cuts);
    }

    function _containsHook(HookConfig[] memory arr, HookConfig h) internal pure returns (bool) {
        for (uint256 i; i < arr.length; ++i) {
            if (HookConfig.unwrap(arr[i]) == HookConfig.unwrap(h)) return true;
        }
        return false;
    }

    // ---- getExecutionData ----

    function test_GetExecutionData_ModuleFunction() public {
        ExecutionManifest memory m;
        m.executionFunctions = new ManifestExecutionFunction[](1);
        m.executionFunctions[0] = ManifestExecutionFunction({
            executionSelector: EXEC_SEL, skipRuntimeValidation: true, allowGlobalValidation: true
        });
        m.executionHooks = new ManifestExecutionHook[](1);
        m.executionHooks[0] =
            ManifestExecutionHook({executionSelector: EXEC_SEL, entityId: 1, isPreHook: true, isPostHook: false});
        vm.prank(admin);
        account.installExecution(address(module), m, "");

        ExecutionDataView memory d = account.getExecutionData(EXEC_SEL);
        assertEq(d.module, address(module), "module");
        assertTrue(d.skipRuntimeValidation, "skip");
        assertTrue(d.allowGlobalValidation, "allowGlobal");
        HookConfig expected = ERC6900TypesLib.packExecHook(ERC6900TypesLib.pack(address(module), 1), true, false);
        assertTrue(_containsHook(d.executionHooks, expected), "exec hook");
    }

    function test_GetExecutionData_NativeFacet() public view {
        ExecutionDataView memory d = account.getExecutionData(DummyFacet.facetPing.selector);
        assertEq(d.module, address(account), "native facet -> account address");
        assertFalse(d.allowGlobalValidation, "plain facet fn does not allow global validation");
    }

    function test_GetExecutionData_NativeExecuteAllowsGlobal() public view {
        assertEq(account.getExecutionData(IERC6900Account.execute.selector).module, address(account), "execute native");
        assertTrue(account.getExecutionData(IERC6900Account.execute.selector).allowGlobalValidation, "execute global");
        assertTrue(
            account.getExecutionData(IERC6900Account.executeBatch.selector).allowGlobalValidation, "executeBatch global"
        );
    }

    function test_GetExecutionData_Unknown() public view {
        ExecutionDataView memory d = account.getExecutionData(0xdeadbeef);
        assertEq(d.module, address(0), "unknown selector -> zero");
    }

    // ---- getValidationData ----

    function test_GetValidationData() public {
        HookConfig valHook = ERC6900TypesLib.packValidationHook(ERC6900TypesLib.pack(address(module), 2));
        HookConfig execHook = ERC6900TypesLib.packExecHook(ERC6900TypesLib.pack(address(module), 3), true, true);
        bytes[] memory hooks = new bytes[](2);
        hooks[0] = abi.encodePacked(HookConfig.unwrap(valHook));
        hooks[1] = abi.encodePacked(HookConfig.unwrap(execHook));
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = EXEC_SEL;
        ValidationConfig cfg = ERC6900TypesLib.pack(address(module), ENTITY, true, true, true);
        vm.prank(admin);
        account.installValidation(cfg, sels, "", hooks);

        ModuleEntity me = ERC6900TypesLib.pack(address(module), ENTITY);
        ValidationDataView memory d = account.getValidationData(me);
        assertEq(uint8(ValidationFlags.unwrap(d.validationFlags)), 0x07, "flags");
        assertEq(d.validationHooks.length, 1, "1 validation hook");
        assertTrue(_containsHook(d.validationHooks, valHook), "val hook");
        assertTrue(_containsHook(d.executionHooks, execHook), "exec hook");
        assertEq(d.selectors.length, 1, "1 selector");
        assertEq(d.selectors[0], EXEC_SEL, "selector");
    }
}
