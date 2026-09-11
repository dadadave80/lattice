// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeployFactory} from "@lattice-script/deploy/DeployFactory.s.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {IReverseRegistrar} from "@lattice/interfaces/external/ens/IReverseRegistrar.sol";
import {Test} from "forge-std/Test.sol";

contract DeployFactoryReverseRegistrar is IReverseRegistrar {
    address public claimant;
    address public owner;

    function claim(address owner_) external returns (bytes32 node) {
        claimant = msg.sender;
        owner = owner_;
        node = keccak256(abi.encodePacked(msg.sender));
    }

    function setName(string memory) external {}
}

contract DeployFactoryTest is Test {
    function test_DeploysOnlyFactoryAgainstExistingRegistry() public {
        LatticeRegistry registry = new LatticeRegistry(address(this));
        DeployFactoryReverseRegistrar registrar = new DeployFactoryReverseRegistrar();
        DeployFactory script = new DeployFactory();
        address reverseRecordOwner = makeAddr("reverseRecordOwner");

        address factory = script.deploy(address(registry), address(registrar), reverseRecordOwner);

        assertEq(address(LatticeFactory(factory).registry()), address(registry));
        assertEq(registrar.claimant(), factory);
        assertEq(registrar.owner(), reverseRecordOwner);
    }
}
