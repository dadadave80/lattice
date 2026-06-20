// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ENSResolver} from "@lattice/ens/ENSResolver.sol";
import {ENSResolverLib, ENS_MANAGER_ROLE} from "@lattice/ens/libraries/ENSResolverLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IENSResolver} from "@lattice/interfaces/IENSResolver.sol";
import {IAddrResolver} from "@lattice/interfaces/external/IAddrResolver.sol";
import {IENS} from "@lattice/interfaces/external/IENS.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockENS
/// @notice Minimal ENS registry storing a resolver + owner per node.
contract MockENS is IENS {
    mapping(bytes32 => address) public resolver;
    mapping(bytes32 => address) public owner;

    function setResolver(bytes32 node, address r) external {
        resolver[node] = r;
    }

    function setOwner(bytes32 node, address o) external {
        owner[node] = o;
    }
}

/// @title MockAddrResolver
/// @notice Minimal EIP-137 address resolver.
contract MockAddrResolver is IAddrResolver {
    mapping(bytes32 => address) public addrOf;

    function setAddr(bytes32 node, address a) external {
        addrOf[node] = a;
    }

    function addr(bytes32 node) external view returns (address payable) {
        return payable(addrOf[node]);
    }
}

/// @title MockENSResolverContract
/// @notice Wrapper that inherits the ENSResolver facet and wires AccessControl + init.
contract MockENSResolverContract is ENSResolver {
    function initialize(address admin, address registry) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin);
        ENSResolverLib.__ENSResolver_init(registry);
        InitializableLib.postInitializer(s);
    }

    function grantRole(bytes32 role, address account) external {
        AccessControlLib.grantRole(role, account);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ENSResolverTester
/// @notice Unit tests for the ENS forward-resolution facet.
contract ENSResolverTester is Test {
    MockENSResolverContract resolverFacet;
    MockENS ens;
    MockAddrResolver addrResolver;

    address admin = address(0xA1);
    address manager = address(0xB2);
    address stranger = address(0xC3);

    bytes32 constant NODE = keccak256("treasury.myproto.eth");
    address constant TARGET = address(0xD00D);

    event EnsRegistrySet(address indexed ensRegistry);

    function setUp() public {
        ens = new MockENS();
        addrResolver = new MockAddrResolver();
        resolverFacet = new MockENSResolverContract();
        resolverFacet.initialize(admin, address(ens));
        vm.prank(admin);
        resolverFacet.grantRole(ENS_MANAGER_ROLE, manager);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            forward resolution
    //////////////////////////////////////////////////////////////////////////*//

    function test_ResolveReturnsAddr() public {
        ens.setResolver(NODE, address(addrResolver));
        addrResolver.setAddr(NODE, TARGET);
        assertEq(resolverFacet.resolve(NODE), TARGET);
    }

    function test_ResolveNoResolverReturnsZero() public view {
        assertEq(resolverFacet.resolve(NODE), address(0));
    }

    function test_ResolverOf() public {
        ens.setResolver(NODE, address(addrResolver));
        assertEq(resolverFacet.resolverOf(NODE), address(addrResolver));
    }

    function test_Subnode() public view {
        bytes32 expected = keccak256(abi.encodePacked(NODE, keccak256(bytes("treasury"))));
        assertEq(resolverFacet.subnode(NODE, "treasury"), expected);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              configuration
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegistryConfiguredAtInit() public view {
        assertEq(resolverFacet.ensRegistry(), address(ens));
    }

    function test_SetEnsRegistryByManager() public {
        MockENS ens2 = new MockENS();
        vm.expectEmit(true, false, false, false, address(resolverFacet));
        emit EnsRegistrySet(address(ens2));
        vm.prank(manager);
        resolverFacet.setEnsRegistry(address(ens2));
        assertEq(resolverFacet.ensRegistry(), address(ens2));
    }

    function test_SetEnsRegistryUnauthorizedReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, ENS_MANAGER_ROLE)
        );
        vm.prank(stranger);
        resolverFacet.setEnsRegistry(address(ens));
    }

    function test_SetEnsRegistryZeroReverts() public {
        vm.expectRevert(IENSResolver.ENSResolverZeroRegistry.selector);
        vm.prank(manager);
        resolverFacet.setEnsRegistry(address(0));
    }

    function test_InitZeroRegistryReverts() public {
        MockENSResolverContract c = new MockENSResolverContract();
        vm.expectRevert(IENSResolver.ENSResolverZeroRegistry.selector);
        c.initialize(admin, address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIENSResolver() public view {
        assertTrue(resolverFacet.supportsInterface(type(IENSResolver).interfaceId));
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IENSResolver).interfaceId, bytes4(0x566ec67d), "IENSResolver interfaceId moved");
    }
}
