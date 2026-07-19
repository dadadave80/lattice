// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "@lattice/utils/Initializable.sol";
import {InvalidInitialization, NotInitializing} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Consumer-shape mock: post-deploy `initialize` guarded by the mixin's modifier.
contract MixinConsumerMock is Initializable {
    uint256 public value;

    function initialize(uint256 _value) external initializer {
        value = _value;
        _initHook();
    }

    /// @dev Reachable only inside an initializer — the module `__X_init` shape.
    function _initHook() internal onlyInitializing {}

    function guarded() external onlyInitializing {}

    function upgradeTo(uint64 _version, uint256 _value) external reinitializer(_version) {
        value = _value;
    }

    function initializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }
}

/// @dev The v0.3.0 regression shape: an initializer-guarded function invoked inside a
/// constructor calls ANOTHER initializer-guarded function. Must finalize exactly once.
contract NestedConstructorMock is Initializable {
    constructor() {
        _outer();
    }

    function _outer() internal initializer {
        _inner();
    }

    function _inner() internal initializer {}
}

contract InitializableMixinTest is Test {
    bytes32 internal constant INIT_TOPIC = keccak256("Initialized(uint64)");

    MixinConsumerMock internal mock;

    function setUp() public {
        mock = new MixinConsumerMock();
    }

    function test_InitializerRunsBodyAndFinalizesOnce() public {
        vm.recordLogs();
        mock.initialize(42);
        assertEq(mock.value(), 42);
        assertEq(mock.initializedVersion(), 1);
        assertEq(_countInitialized(), 1);
    }

    function test_SecondInitializeReverts() public {
        mock.initialize(42);
        vm.expectRevert(InvalidInitialization.selector);
        mock.initialize(7);
    }

    function test_OnlyInitializingRevertsOutsideInitializer() public {
        mock.initialize(42);
        vm.expectRevert(NotInitializing.selector);
        mock.guarded();
    }

    function test_ReinitializerBumpsVersionOnceEach() public {
        mock.initialize(42);
        mock.upgradeTo(2, 7);
        assertEq(mock.value(), 7);
        assertEq(mock.initializedVersion(), 2);
        vm.expectRevert(InvalidInitialization.selector);
        mock.upgradeTo(2, 9);
    }

    function test_NestedConstructorInitializerFinalizesOnce() public {
        vm.recordLogs();
        new NestedConstructorMock();
        assertEq(_countInitialized(), 1);
    }

    function _countInitialized() internal returns (uint256 n_) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == INIT_TOPIC) ++n_;
        }
    }
}
