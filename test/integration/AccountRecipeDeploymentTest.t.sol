// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Selectors} from "@diamond-test/helpers/Selectors.sol";
import {IDiamondCut} from "@diamond/interfaces/IDiamondCut.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccount} from "@lattice-script/base/accounts/DeployAccount.s.sol";
import {DeployAccount6900} from "@lattice-script/base/accounts/DeployAccount6900.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {ERC6900ModuleManager} from "@lattice/accounts/erc6900/ERC6900ModuleManager.sol";
import {ModularAccount6900} from "@lattice/accounts/erc6900/ModularAccount6900.sol";
import {AccountDiamond} from "@lattice/accounts/erc7579/AccountDiamond.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {ERC7579ModuleConfig} from "@lattice/accounts/erc7579/ERC7579ModuleConfig.sol";
import {ERC7821Executor} from "@lattice/accounts/erc7579/ERC7821Executor.sol";
import {
    ERC7579ModuleConfigLib,
    FALLBACK_CALLTYPE_CALL
} from "@lattice/accounts/erc7579/libraries/ERC7579ModuleConfigLib.sol";
import {ERC4337_VALIDATION_STORAGE_SLOT} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {IERC6900Executor} from "@lattice/interfaces/accounts/IERC6900Executor.sol";
import {IModuleConfig} from "@lattice/interfaces/accounts/IModuleConfig.sol";
import {ExecutionManifest, ManifestExecutionFunction} from "@lattice/interfaces/external/ercs/IERC6900.sol";
import {IERC7579ModuleConfig, MODULE_TYPE_FALLBACK} from "@lattice/interfaces/external/ercs/IERC7579.sol";
import {Call} from "@lattice/interfaces/external/ercs/IERC7821.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Upgrade registration fixture: module configuration has no bootstrap state beyond interface flags.
contract RecipeModuleConfigInit {
    function init() external {
        ERC7579ModuleConfigLib.registerInterfaces();
    }
}

/// @notice A fallback handler whose return value proves the ERC-2771 caller suffix survived dispatch.
contract RecipeFallbackHandler {
    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function isModuleType(uint256 kind) external pure returns (bool) {
        return kind == MODULE_TYPE_FALLBACK;
    }

    function recipeCaller() external pure returns (address sender) {
        assembly ("memory-safe") {
            sender := shr(96, calldataload(sub(calldatasize(), 20)))
        }
    }
}

/// @notice Execution-module fixture records external CALL context, rather than account delegatecall context.
contract RecipeExecutionModule {
    address public lastSender;
    address public lastThis;

    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }

    function recipePing() external returns (uint256) {
        lastSender = msg.sender;
        lastThis = address(this);
        return 209;
    }
}

interface IUnrecognizedRecipeCall {
    function unrecognizedRecipeCall() external;
}

/// @title AccountRecipeDeploymentTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Exercise the actual run entrypoints: generic Lattice assembly cannot pass these dispatch regressions.
contract AccountRecipeDeploymentTest is Test {
    address internal constant ENTRY_POINT = address(0xE117);
    address internal constant OWNER = address(0xA11CE);
    bytes32 internal constant BATCH_MODE = 0x0100000000000000000000000000000000000000000000000000000000000000;

    function test_Run7579UsesSpecializedRuntime() public {
        address account = new DeployAccount().run(ENTRY_POINT, OWNER);
        assertEq(account.codehash, address(new AccountDiamond()).codehash);
        assertEq(AccountSigner(account).owner(), OWNER);
        assertEq(ERC4337Validation(account).entryPoint(), ENTRY_POINT);
        assertTrue(AccessControl(account).hasRole(bytes32(0), account));
        assertFalse(AccessControl(account).hasRole(bytes32(0), OWNER));
    }

    function test_Run6900UsesSpecializedRuntime() public {
        address account = new DeployAccount6900().run(ENTRY_POINT, OWNER);
        assertEq(account.codehash, address(new ModularAccount6900()).codehash);
        // The 6900 validation facet deliberately has no EntryPoint getter; both paths share this namespace.
        assertEq(address(uint160(uint256(vm.load(account, ERC4337_VALIDATION_STORAGE_SLOT)))), ENTRY_POINT);
        assertTrue(AccessControl(account).hasRole(bytes32(0), OWNER));
    }

    function test_Run7579DispatchesInstalledHandler() public {
        address account = new DeployAccount().run(ENTRY_POINT, OWNER);
        ERC7579ModuleConfig config = new ERC7579ModuleConfig();
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(config), FacetCutAction.Add, Selectors.decode(config.exportSelectors()));
        RecipeModuleConfigInit init = new RecipeModuleConfigInit();
        _executeSelf(
            account, abi.encodeCall(IDiamondCut.diamondCut, (cuts, address(init), abi.encodeCall(init.init, ())))
        );

        RecipeFallbackHandler handler = new RecipeFallbackHandler();
        _executeSelf(
            account,
            abi.encodeCall(
                IERC7579ModuleConfig.installModule,
                (
                    MODULE_TYPE_FALLBACK,
                    address(handler),
                    abi.encode(RecipeFallbackHandler.recipeCaller.selector, FALLBACK_CALLTYPE_CALL, bytes(""))
                )
            )
        );
        address caller = address(0xCA11E2);
        vm.prank(caller);
        assertEq(RecipeFallbackHandler(account).recipeCaller(), caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IModuleConfig.NoFallbackHandler.selector, IUnrecognizedRecipeCall.unrecognizedRecipeCall.selector
            )
        );
        IUnrecognizedRecipeCall(account).unrecognizedRecipeCall();
    }

    function test_Run6900DispatchesInstalledExecution() public {
        address account = new DeployAccount6900().run(ENTRY_POINT, OWNER);
        RecipeExecutionModule module = new RecipeExecutionModule();
        ExecutionManifest memory manifest;
        manifest.executionFunctions = new ManifestExecutionFunction[](1);
        manifest.executionFunctions[0] = ManifestExecutionFunction({
            executionSelector: RecipeExecutionModule.recipePing.selector,
            skipRuntimeValidation: true,
            allowGlobalValidation: false
        });
        vm.prank(OWNER);
        ERC6900ModuleManager(account).installExecution(address(module), manifest, "");
        assertEq(RecipeExecutionModule(account).recipePing(), 209);
        assertEq(module.lastSender(), account);
        assertEq(module.lastThis(), address(module));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC6900Executor.UnrecognizedFunction.selector, IUnrecognizedRecipeCall.unrecognizedRecipeCall.selector
            )
        );
        IUnrecognizedRecipeCall(account).unrecognizedRecipeCall();
    }

    function _executeSelf(address account, bytes memory data) private {
        Call[] memory calls = new Call[](1);
        calls[0] = Call(account, 0, data);
        vm.prank(ENTRY_POINT);
        ERC7821Executor(payable(account)).execute(BATCH_MODE, abi.encode(calls));
    }
}
