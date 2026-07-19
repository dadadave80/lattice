// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {ENSResolverTestBase} from "@lattice-test/base/ENSResolverTestBase.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {ENSResolver} from "@lattice/ens/ENSResolver.sol";
import {ENS_MANAGER_ROLE} from "@lattice/ens/libraries/ENSResolverLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IENSResolver} from "@lattice/interfaces/ens/IENSResolver.sol";
import {IAddrResolver} from "@lattice/interfaces/external/ens/IAddrResolver.sol";
import {IENS} from "@lattice/interfaces/external/ens/IENS.sol";

/// @title MockENS
/// @notice Minimal ENS registry storing a resolver + owner per node. Kept as a test fixture (external contract the
///         facet reads — NOT the facet under test).
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
/// @notice Minimal EIP-137 address resolver. Kept as a test fixture.
contract MockAddrResolver is IAddrResolver {
    mapping(bytes32 => address) public addrOf;

    function setAddr(bytes32 node, address a) external {
        addrOf[node] = a;
    }

    function addr(bytes32 node) external view returns (address payable) {
        return payable(addrOf[node]);
    }
}

/// @title ENSResolverTest
/// @notice Exercises the ENS forward-resolution facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployENSResolver} script (see {ENSResolverTestBase}) — every resolution read routes through the
///         diamond's `delegatecall` dispatch, not a flattened inheritance mock. Role gating is enforced by the
///         cut-in `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`. The external
///         `MockENS`/`MockAddrResolver` stay test fixtures (they are NOT the facet under test).
contract ENSResolverTest is ENSResolverTestBase {
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
        diamond = _deployENSResolver(admin, address(ens));
        resolverFacet = ENSResolver(diamond);
        vm.prank(admin);
        IAccessControl(diamond).grantRole(ENS_MANAGER_ROLE, manager);
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
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, address(0));
        LatticeDiamond d = new LatticeDiamond();
        vm.expectRevert(IENSResolver.ENSResolverZeroRegistry.selector);
        d.initialize(cuts, init, initCalldata);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIENSResolver() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IENSResolver).interfaceId));
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IENSResolver).interfaceId, bytes4(0x566ec67d), "IENSResolver interfaceId moved");
    }
}
