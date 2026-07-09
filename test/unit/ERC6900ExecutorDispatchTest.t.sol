// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC6900ModuleManager} from "@lattice/accounts/erc6900/ERC6900ModuleManager.sol";
import {ModularAccount6900} from "@lattice/accounts/erc6900/ModularAccount6900.sol";
import {ERC6900TypesLib} from "@lattice/accounts/erc6900/libraries/ERC6900TypesLib.sol";
import {IERC6900Executor} from "@lattice/interfaces/accounts/IERC6900Executor.sol";
import {
    DIRECT_CALL_VALIDATION_ENTITY_ID,
    ExecutionManifest,
    ManifestExecutionFunction,
    ManifestExecutionHook,
    ValidationConfig
} from "@lattice/interfaces/external/IERC6900.sol";
import {Test} from "forge-std/Test.sol";

interface IFoo {
    function foo() external returns (uint256);
    function bar() external returns (uint256);
}

/// @dev A cut facet, to prove facet selectors win over the execution registry.
contract DummyFacet {
    function facetPing() external pure returns (uint256) {
        return 7;
    }
}

/// @dev An ERC-6900 execution module exposing `foo()` and its own pre/post execution hooks (manifest exec hooks
///      are implemented by the installing module, keyed by entityId). Records context to prove the account
///      reaches it by CALL (its own storage; `address(this) == module`, `msg.sender == account`).
contract MockExecModule {
    address public lastThis;
    address public lastSender;
    bool public doRevert;
    uint256 public preCount;
    uint256 public postCount;
    bytes public lastPreData;

    function setRevert(bool v) external {
        doRevert = v;
    }

    function foo() external returns (uint256) {
        if (doRevert) revert("foo failed");
        lastThis = address(this);
        lastSender = msg.sender;
        return 99;
    }

    function preExecutionHook(uint32, address, uint256, bytes calldata data) external returns (bytes memory) {
        ++preCount;
        lastPreData = data;
        return hex"c0ffee";
    }

    function postExecutionHook(uint32, bytes calldata) external {
        ++postCount;
    }

    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function moduleId() external pure returns (string memory) {
        return "lattice.mockexec.1.0.0";
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

contract MockAccount6900 is ModularAccount6900, AccessControl, ERC6900ModuleManager {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, ERC6900ModuleManager)
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

contract ERC6900ExecutorDispatchTest is Test {
    MockAccount6900 account;
    MockExecModule module;
    DummyFacet dummy;
    address admin = address(0xA11CE);

    function setUp() public {
        dummy = new DummyFacet();
        module = new MockExecModule();
        account = new MockAccount6900();

        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DummyFacet.facetPing.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Add, functionSelectors: sels});
        account.initialize(admin, cuts);
    }

    // ---- manifest helpers ----

    function _fooManifest(bool skipRuntimeValidation) internal pure returns (ExecutionManifest memory m) {
        m.executionFunctions = new ManifestExecutionFunction[](1);
        m.executionFunctions[0] = ManifestExecutionFunction({
            executionSelector: IFoo.foo.selector,
            skipRuntimeValidation: skipRuntimeValidation,
            allowGlobalValidation: false
        });
    }

    function _installFoo(bool skip) internal {
        vm.prank(admin);
        account.installExecution(address(module), _fooManifest(skip), "");
    }

    // ---- dispatch ----

    function test_Dispatch_SkipRuntimeValidation_Open() public {
        _installFoo(true);
        assertEq(IFoo(address(account)).foo(), 99, "module fn not dispatched");
    }

    function test_Dispatch_ModuleRunsInOwnContext() public {
        _installFoo(true);
        IFoo(address(account)).foo();
        assertEq(module.lastThis(), address(module), "module ran via CALL (own context)");
        assertEq(module.lastSender(), address(account), "msg.sender inside module is the account");
    }

    function test_Dispatch_UnrecognizedFunction() public {
        vm.expectRevert(abi.encodeWithSelector(IERC6900Executor.UnrecognizedFunction.selector, IFoo.bar.selector));
        IFoo(address(account)).bar();
    }

    function test_Dispatch_FacetWinsOverRegistry() public {
        // facetPing is a cut facet selector; the fallback delegatecalls the facet, never the exec registry.
        assertEq(DummyFacet(address(account)).facetPing(), 7, "facet selector not dispatched");
    }

    function test_Dispatch_RunsExecHooks() public {
        ExecutionManifest memory m = _fooManifest(true);
        m.executionHooks = new ManifestExecutionHook[](1);
        m.executionHooks[0] = ManifestExecutionHook({
            executionSelector: IFoo.foo.selector, entityId: 1, isPreHook: true, isPostHook: true
        });
        vm.prank(admin);
        account.installExecution(address(module), m, "");

        IFoo(address(account)).foo();
        assertEq(module.preCount(), 1, "pre hook ran");
        assertEq(module.postCount(), 1, "post hook ran");
        assertEq(module.lastPreData(), abi.encodeWithSelector(IFoo.foo.selector), "pre hook got the call data");
    }

    function test_Dispatch_BubblesModuleRevert() public {
        _installFoo(true);
        module.setRevert(true);
        vm.expectRevert(bytes("foo failed"));
        IFoo(address(account)).foo();
    }

    function test_Dispatch_RequiresDirectCallValidation() public {
        _installFoo(false); // skipRuntimeValidation = false → a direct call needs a direct-call validation
        address caller = address(0xCA11E2);

        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IERC6900Executor.ValidationFunctionMissing.selector, IFoo.foo.selector));
        IFoo(address(account)).foo();

        // Install a direct-call validation: the validation "module" is the authorized caller, entityId = max.
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = IFoo.foo.selector;
        ValidationConfig cfg = ERC6900TypesLib.pack(caller, DIRECT_CALL_VALIDATION_ENTITY_ID, false, false, false);
        vm.prank(admin);
        account.installValidation(cfg, sels, "", new bytes[](0));

        vm.prank(caller);
        assertEq(IFoo(address(account)).foo(), 99, "direct-call validation should authorize");
    }
}
