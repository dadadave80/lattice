// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ArachnidDeployer} from "@lattice-script/lib/ArachnidDeployer.sol";
import {ArachnidProxy} from "@lattice-test/helpers/ArachnidProxy.sol";
import {Test} from "forge-std/Test.sol";

contract ArachnidDeploymentTarget {
    function value() external pure returns (uint256) {
        return 42;
    }
}

contract ArachnidDeployerHarness {
    function deploy(bytes32 salt, bytes memory initCode) external returns (address) {
        return ArachnidDeployer.deploy(salt, initCode);
    }
}

contract ArachnidDeployerTest is Test {
    ArachnidDeployerHarness internal harness;
    bytes32 internal constant SALT = keccak256("lattice.test.arachnid-deployer");

    function setUp() public {
        vm.etch(ArachnidProxy.PROXY, ArachnidProxy.RUNTIME);
        harness = new ArachnidDeployerHarness();
    }

    function test_DeployUsesRawSaltAndReturnsFunctionalCode() public {
        bytes memory initCode = type(ArachnidDeploymentTarget).creationCode;
        address expected = address(
            uint160(uint256(keccak256(abi.encodePacked(hex"ff", ArachnidProxy.PROXY, SALT, keccak256(initCode)))))
        );
        assertEq(ArachnidDeployer.predict(SALT, keccak256(initCode)), expected);
        address deployed = harness.deploy(SALT, initCode);
        assertEq(deployed, expected);
        assertEq(ArachnidDeploymentTarget(deployed).value(), 42);
    }

    function test_DeployWithoutProxyReverts() public {
        vm.etch(ArachnidProxy.PROXY, "");
        vm.expectRevert(bytes("ArachnidDeployer: install proxy 0x4e59b44847b379578588920cA78FbF26c0B4956C"));
        harness.deploy(SALT, type(ArachnidDeploymentTarget).creationCode);
    }

    function test_DeployAtOccupiedAddressReverts() public {
        harness.deploy(SALT, type(ArachnidDeploymentTarget).creationCode);
        vm.expectRevert(bytes("ArachnidDeployer: proxy deployment reverted"));
        harness.deploy(SALT, type(ArachnidDeploymentTarget).creationCode);
    }

    function test_DeployWithRevertingInitCodeReverts() public {
        vm.expectRevert(bytes("ArachnidDeployer: proxy deployment reverted"));
        harness.deploy(SALT, hex"60006000fd");
    }

    function testFuzz_DeployRejectsReturnLengthOtherThan20(uint8 length) public {
        vm.assume(length != 20);
        vm.mockCall(ArachnidProxy.PROXY, bytes(""), new bytes(length));
        vm.expectRevert(bytes("ArachnidDeployer: invalid proxy return"));
        harness.deploy(SALT, type(ArachnidDeploymentTarget).creationCode);
    }

    function test_DeployRejectsAnUnexpectedAddress() public {
        vm.mockCall(ArachnidProxy.PROXY, bytes(""), abi.encodePacked(address(1)));
        vm.expectRevert(bytes("ArachnidDeployer: unexpected deployment address"));
        harness.deploy(SALT, type(ArachnidDeploymentTarget).creationCode);
    }

    function test_DeployRejectsAnAddressWithoutCode() public {
        bytes memory initCode = type(ArachnidDeploymentTarget).creationCode;
        address expected = ArachnidDeployer.predict(SALT, keccak256(initCode));
        vm.mockCall(ArachnidProxy.PROXY, bytes(""), abi.encodePacked(expected));
        vm.expectRevert(bytes("ArachnidDeployer: empty deployment"));
        harness.deploy(SALT, initCode);
    }

    function test_DeployRejectsInitCodeReturningEmptyCode() public {
        vm.expectRevert(bytes("ArachnidDeployer: empty deployment"));
        harness.deploy(SALT, hex"60006000f3");
    }
}
