// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC6900Executor} from "@lattice/accounts/erc6900/ERC6900Executor.sol";
import {ERC6900ModuleManager} from "@lattice/accounts/erc6900/ERC6900ModuleManager.sol";
import {ModularAccount6900} from "@lattice/accounts/erc6900/ModularAccount6900.sol";
import {ERC6900TypesLib} from "@lattice/accounts/erc6900/libraries/ERC6900TypesLib.sol";
import {IERC6900Executor} from "@lattice/interfaces/accounts/IERC6900Executor.sol";
import {
    HookConfig,
    IERC6900Account,
    ModuleEntity,
    ValidationConfig
} from "@lattice/interfaces/external/ercs/IERC6900.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test} from "forge-std/Test.sol";

contract Target {
    uint256 public v;

    function setV(uint256 x) external {
        v = x;
    }
}

/// @dev An ERC-6900 validation module (+ its own hooks) that records calls.
contract MockValidation {
    bool public validatedRuntime;
    bool public doRevert;
    uint256 public preValHookCount;
    uint256 public execPreCount;
    uint256 public execPostCount;

    function setRevert(bool v) external {
        doRevert = v;
    }

    function validateRuntime(address, uint32, address, uint256, bytes calldata, bytes calldata) external {
        if (doRevert) revert("validation failed");
        validatedRuntime = true;
    }

    function preRuntimeValidationHook(uint32, address, uint256, bytes calldata, bytes calldata) external {
        ++preValHookCount;
    }

    function preExecutionHook(uint32, address, uint256, bytes calldata) external returns (bytes memory) {
        ++execPreCount;
        return "";
    }

    function postExecutionHook(uint32, bytes calldata) external {
        ++execPostCount;
    }

    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function moduleId() external pure returns (string memory) {
        return "lattice.mockval.1.0.0";
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

contract MockRtAccount is ModularAccount6900, AccessControl, ERC6900ModuleManager, ERC6900Executor {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, ERC6900ModuleManager, ERC6900Executor)
        returns (bytes memory)
    {}

    function initialize(address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        InitializableLib.postInitializer(s);
    }
}

contract ERC6900ExecutorRuntimeValidationTest is Test {
    MockRtAccount account;
    MockValidation val;
    Target target;
    address admin = address(0xA11CE);

    uint32 constant ENTITY = 5;

    function setUp() public {
        account = new MockRtAccount();
        account.initialize(admin);
        val = new MockValidation();
        target = new Target();
    }

    function _me() internal view returns (ModuleEntity) {
        return ERC6900TypesLib.pack(address(val), ENTITY);
    }

    function _install(bool global, bytes4[] memory sels, bytes[] memory hooks) internal {
        ValidationConfig cfg = ERC6900TypesLib.pack(address(val), ENTITY, global, false, false);
        vm.prank(admin);
        account.installValidation(cfg, sels, "", hooks);
    }

    function _auth(bool global) internal view returns (bytes memory) {
        return abi.encodePacked(ModuleEntity.unwrap(_me()), global ? bytes1(0x01) : bytes1(0x00));
    }

    function _execData(uint256 x) internal view returns (bytes memory) {
        return abi.encodeCall(IERC6900Account.execute, (address(target), 0, abi.encodeCall(Target.setV, (x))));
    }

    function _sel(bytes4 a) internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = a;
    }

    function test_RuntimeVal_ValidatesAndExecutes() public {
        _install(false, _sel(IERC6900Account.execute.selector), new bytes[](0));
        account.executeWithRuntimeValidation(_execData(42), _auth(false));
        assertTrue(val.validatedRuntime(), "validateRuntime ran");
        assertEq(target.v(), 42, "inner execute ran");
    }

    function test_RuntimeVal_GlobalValidation() public {
        _install(true, new bytes4[](0), new bytes[](0)); // global; execute opts into global validation
        account.executeWithRuntimeValidation(_execData(7), _auth(true));
        assertEq(target.v(), 7, "global validation authorized");
    }

    function test_RuntimeVal_RevertValidationReverts() public {
        _install(false, _sel(IERC6900Account.execute.selector), new bytes[](0));
        val.setRevert(true);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC6900Executor.RuntimeValidationFunctionReverted.selector,
                address(val),
                ENTITY,
                abi.encodeWithSignature("Error(string)", "validation failed")
            )
        );
        account.executeWithRuntimeValidation(_execData(1), _auth(false));
    }

    function test_RuntimeVal_RevertNotApplicable() public {
        _install(false, new bytes4[](0), new bytes[](0)); // no selectors, not global → cannot validate execute
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC6900Executor.ValidationFunctionMissing.selector, IERC6900Account.execute.selector
            )
        );
        account.executeWithRuntimeValidation(_execData(1), _auth(false));
    }

    function test_RuntimeVal_RunsPreValidationAndExecHooks() public {
        bytes[] memory hooks = new bytes[](2);
        // a pre-validation hook and a validation-associated exec hook, both implemented by the validation module
        HookConfig valHook = ERC6900TypesLib.packValidationHook(ERC6900TypesLib.pack(address(val), 1));
        HookConfig execHook = ERC6900TypesLib.packExecHook(ERC6900TypesLib.pack(address(val), 2), true, true);
        hooks[0] = abi.encodePacked(HookConfig.unwrap(valHook));
        hooks[1] = abi.encodePacked(HookConfig.unwrap(execHook));
        _install(false, _sel(IERC6900Account.execute.selector), hooks);

        account.executeWithRuntimeValidation(_execData(9), _auth(false));
        assertEq(val.preValHookCount(), 1, "pre-validation hook ran");
        assertEq(val.execPreCount(), 1, "validation exec pre-hook ran");
        assertEq(val.execPostCount(), 1, "validation exec post-hook ran");
        assertEq(target.v(), 9, "inner execute ran");
    }
}
