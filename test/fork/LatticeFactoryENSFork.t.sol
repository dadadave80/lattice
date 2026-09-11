// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {IENS} from "@lattice/interfaces/external/ens/IENS.sol";
import {Test} from "forge-std/Test.sol";

interface IFactoryReverseRegistrar {
    function node(address addr) external pure returns (bytes32);
    function setNameForAddr(address addr, address owner, address resolver, string calldata name)
        external
        returns (bytes32);
}

interface IFactoryNameResolver {
    function name(bytes32 node) external view returns (string memory);
    function setName(bytes32 node, string calldata name) external;
}

/// @title LatticeFactoryENSFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Sepolia-fork proof that the real ENS registrar accepts the Factory's constructor claim and gives
///         the explicit record owner authority to set the reverse name through the registrar's resolver.
contract LatticeFactoryENSFork is Test {
    address internal constant SEPOLIA_ENS_REGISTRY = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
    address internal constant SEPOLIA_REVERSE_REGISTRAR = 0xA0a1AbcDAe1a2a4A2EF8e9113Ff0e02DD81DC0C6;
    uint256 internal constant DEFAULT_FORK_BLOCK = 11_239_288;

    address internal reverseRecordOwner = makeAddr("reverseRecordOwner");

    function setUp() public {
        if (bytes(vm.envOr("SEPOLIA_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("sepolia", vm.envOr("SEPOLIA_FORK_BLOCK", DEFAULT_FORK_BLOCK));
    }

    function test_Fork_ConstructorClaimCanBeNamedByExplicitOwner() public {
        LatticeRegistry registry = new LatticeRegistry(address(this));
        LatticeFactory factory = new LatticeFactory(registry, SEPOLIA_REVERSE_REGISTRAR, reverseRecordOwner);

        bytes32 node = IFactoryReverseRegistrar(SEPOLIA_REVERSE_REGISTRAR).node(address(factory));
        assertEq(IENS(SEPOLIA_ENS_REGISTRY).owner(node), reverseRecordOwner, "reverse owner");

        address resolver = IENS(SEPOLIA_ENS_REGISTRY).resolver(node);
        assertTrue(resolver != address(0), "default resolver");

        string memory ensName = "factory.lattice.studio.eth";
        vm.prank(reverseRecordOwner);
        IFactoryNameResolver(resolver).setName(node, ensName);
        assertEq(IFactoryNameResolver(resolver).name(node), ensName, "reverse name");

        vm.expectRevert();
        IFactoryNameResolver(resolver).setName(node, "unauthorized.lattice.studio.eth");

        vm.prank(reverseRecordOwner);
        vm.expectRevert();
        IFactoryReverseRegistrar(SEPOLIA_REVERSE_REGISTRAR)
            .setNameForAddr(address(factory), reverseRecordOwner, resolver, ensName);
    }
}
