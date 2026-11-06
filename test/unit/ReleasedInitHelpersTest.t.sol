// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {ArachnidDeployer} from "@lattice-script/lib/ArachnidDeployer.sol";
import {ArachnidProxy} from "@lattice-test/helpers/ArachnidProxy.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {Test} from "forge-std/Test.sol";

contract ReleasedInitHelpersHarness is BaseDeploy {
    function wrap(address moduleInit, bytes memory data, address admin) external returns (address, bytes memory) {
        return _withAdminUpgradeableIntrospection(moduleInit, data, admin);
    }

    function resolve(string memory name) external returns (address) {
        return _init(name);
    }

    function wrapImmutable(address moduleInit, bytes memory data) external returns (address, bytes memory) {
        return _withImmutableIntrospection(moduleInit, data);
    }

    function decodePlan(bytes calldata data) external pure returns (address[] memory inits, bytes[] memory calls) {
        return abi.decode(data[4:], (address[], bytes[]));
    }
}

contract ReleasedInitHelpersTest is Test {
    function test_CommonHelpersReuseReleasedAddresses() public {
        vm.etch(ArachnidProxy.PROXY, ArachnidProxy.RUNTIME);
        ReleasedInitHelpersHarness harness = new ReleasedInitHelpersHarness();
        (address init, bytes memory data) = harness.wrap(address(1), hex"1234", address(2));
        assertEq(init, _released("MultiInit", "MultiInit.sol:MultiInit"), "fresh MultiInit");
        (address[] memory inits,) = harness.decodePlan(data);
        assertEq(inits[1], _released("AccessControlInit", "src/access/AccessControlInit.sol:AccessControlInit"));
        assertEq(
            inits[2],
            _released("DiamondIntrospectionInit", "src/utils/DiamondIntrospectionInit.sol:DiamondIntrospectionInit")
        );
    }

    function test_RepeatWrappingDoesNotCreateFreshHelpers() public {
        vm.etch(ArachnidProxy.PROXY, ArachnidProxy.RUNTIME);
        ReleasedInitHelpersHarness harness = new ReleasedInitHelpersHarness();
        (address first,) = harness.wrap(address(1), hex"1234", address(2));
        uint64 nonce = vm.getNonce(address(harness));
        vm.mockCallRevert(ArachnidProxy.PROXY, bytes(""), bytes("helper already released"));
        (address second, bytes memory data) = harness.wrap(address(3), hex"5678", address(4));
        assertEq(first, second);
        assertEq(vm.getNonce(address(harness)), nonce, "fresh helper created through plain CREATE");
        (address[] memory inits, bytes[] memory calls) = harness.decodePlan(data);
        assertEq(inits[0], address(3));
        assertEq(calls[0], hex"5678");
        (address immutableInit,) = harness.wrapImmutable(address(3), hex"5678");
        assertEq(immutableInit, first);
    }

    function test_InitHelperFallsBackLocallyWithoutProxy() public {
        vm.etch(ArachnidProxy.PROXY, "");
        ReleasedInitHelpersHarness harness = new ReleasedInitHelpersHarness();
        address expected = vm.computeCreateAddress(address(harness), vm.getNonce(address(harness)));
        address deployed = harness.resolve("VotesInit");
        assertEq(deployed, expected);
        assertEq(deployed.codehash, keccak256(vm.getDeployedCode("src/governance/VotesInit.sol:VotesInit")));
    }

    function test_InitHelperRejectsConstructorBoundAccountInit() public {
        ReleasedInitHelpersHarness harness = new ReleasedInitHelpersHarness();
        vm.expectRevert(bytes("BaseDeploy: AccountInit is not in InitInventory"));
        harness.resolve("AccountInit");
    }

    function _released(string memory name, string memory artifact) internal view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked("lattice.", name, ".", LatticeVersion.VERSION));
        return ArachnidDeployer.predict(salt, keccak256(vm.getCode(artifact)));
    }
}
