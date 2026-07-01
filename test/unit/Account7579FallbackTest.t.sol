// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccountDiamond} from "@lattice/accounts/erc7579/AccountDiamond.sol";
import {ERC7579ModuleConfig} from "@lattice/accounts/erc7579/ERC7579ModuleConfig.sol";
import {
    ERC7579ModuleConfigLib,
    FALLBACK_CALLTYPE_CALL,
    FALLBACK_CALLTYPE_DELEGATECALL
} from "@lattice/accounts/erc7579/libraries/ERC7579ModuleConfigLib.sol";
import {IModuleConfig} from "@lattice/interfaces/accounts/IModuleConfig.sol";
import {MODULE_TYPE_FALLBACK} from "@lattice/interfaces/external/IERC7579.sol";
import {Test} from "forge-std/Test.sol";

/// @dev The selectors a fallback handler / facet exposes through the account.
interface IExtended {
    function ping() external returns (uint256);
    function whoCalled() external returns (address);
    function selfAddr() external returns (address);
    function facetPing() external returns (uint256);
}

/// @dev A facet cut into the diamond, so the facet map owns `facetPing()` (for the shadow / facet-wins cases).
contract DummyFacet {
    function facetPing() external pure returns (uint256) {
        return 7;
    }
}

/// @dev CALL-type fallback handler. `whoCalled` recovers the ERC-2771 appended caller.
contract CallHandler {
    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function isModuleType(uint256 t) external pure returns (bool) {
        return t == MODULE_TYPE_FALLBACK;
    }

    function ping() external pure returns (uint256) {
        return 42;
    }

    function whoCalled() external pure returns (address sender) {
        assembly {
            sender := shr(96, calldataload(sub(calldatasize(), 20)))
        }
    }
}

/// @dev DELEGATECALL-type fallback handler: `selfAddr` returns `address(this)`, which under delegatecall is the
///      account, proving the handler runs in the account's context.
contract DelegateHandler {
    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function isModuleType(uint256 t) external pure returns (bool) {
        return t == MODULE_TYPE_FALLBACK;
    }

    function selfAddr() external view returns (address) {
        return address(this);
    }
}

/// @dev An AccountDiamond-based account with one cut facet (DummyFacet) plus the access + module-config facets.
contract MockAccountDiamond is AccountDiamond, AccessControl, ERC7579ModuleConfig {
    function initialize(address admin_, FacetCut[] calldata cuts) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ERC7579ModuleConfigLib.__ERC7579ModuleConfig_init();
        DiamondLib.diamondCut(cuts, address(0), msg.data[0:0]);
        InitializableLib.postInitializer(s);
    }
}

contract Account7579FallbackTest is Test {
    MockAccountDiamond account;
    DummyFacet dummy;
    address admin = address(0xA11CE);

    function setUp() public {
        dummy = new DummyFacet();
        account = new MockAccountDiamond();
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DummyFacet.facetPing.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Add, functionSelectors: sels});
        account.initialize(admin, cuts);
    }

    function _installCall(address handler, bytes4 selector) internal {
        vm.prank(admin);
        account.installModule(MODULE_TYPE_FALLBACK, handler, abi.encode(selector, FALLBACK_CALLTYPE_CALL, bytes("")));
    }

    function test_Fallback_CallRoutes() public {
        CallHandler h = new CallHandler();
        _installCall(address(h), CallHandler.ping.selector);
        assertTrue(account.isModuleInstalled(MODULE_TYPE_FALLBACK, address(h), abi.encode(CallHandler.ping.selector)));
        assertEq(IExtended(address(account)).ping(), 42, "CALL fallback not routed");
    }

    function test_Fallback_CallAppendsSender() public {
        CallHandler h = new CallHandler();
        _installCall(address(h), CallHandler.whoCalled.selector);
        address caller = address(0xCA11E2);
        vm.prank(caller);
        assertEq(IExtended(address(account)).whoCalled(), caller, "ERC-2771 sender not appended");
    }

    function test_Fallback_DelegateRunsInAccountContext() public {
        DelegateHandler h = new DelegateHandler();
        vm.prank(admin);
        account.installModule(
            MODULE_TYPE_FALLBACK,
            address(h),
            abi.encode(DelegateHandler.selfAddr.selector, FALLBACK_CALLTYPE_DELEGATECALL, bytes(""))
        );
        assertEq(IExtended(address(account)).selfAddr(), address(account), "DELEGATECALL not in account context");
    }

    function test_Fallback_FacetWinsOverRegistry() public {
        // facetPing is owned by DummyFacet (a cut facet); it dispatches to the facet, never the registry.
        assertEq(IExtended(address(account)).facetPing(), 7, "facet selector not dispatched");
    }

    function test_Fallback_CannotShadowFacet() public {
        CallHandler h = new CallHandler();
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IModuleConfig.FallbackShadowsFacet.selector, DummyFacet.facetPing.selector)
        );
        account.installModule(
            MODULE_TYPE_FALLBACK,
            address(h),
            abi.encode(DummyFacet.facetPing.selector, FALLBACK_CALLTYPE_CALL, bytes(""))
        );
    }

    function test_Fallback_UnknownSelectorReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IModuleConfig.NoFallbackHandler.selector, IExtended.ping.selector));
        IExtended(address(account)).ping();
    }

    function test_Fallback_RejectsBadCallType() public {
        CallHandler h = new CallHandler();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IModuleConfig.UnsupportedFallbackCallType.selector, bytes1(0x01)));
        account.installModule(
            MODULE_TYPE_FALLBACK, address(h), abi.encode(CallHandler.ping.selector, bytes1(0x01), bytes(""))
        );
    }

    function test_Fallback_Uninstall() public {
        CallHandler h = new CallHandler();
        _installCall(address(h), CallHandler.ping.selector);
        assertEq(IExtended(address(account)).ping(), 42, "not routed pre-uninstall");
        vm.prank(admin);
        account.uninstallModule(MODULE_TYPE_FALLBACK, address(h), abi.encode(CallHandler.ping.selector, bytes("")));
        vm.expectRevert(abi.encodeWithSelector(IModuleConfig.NoFallbackHandler.selector, CallHandler.ping.selector));
        IExtended(address(account)).ping();
    }
}
