// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployENSResolverV2} from "@lattice-script/base/ens/DeployENSResolverV2.s.sol";
import {ENSResolverV2TestBase} from "@lattice-test/base/ENSResolverV2TestBase.sol";
import {MultiInitErrors} from "@lattice-test/helpers/MultiInitErrors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {ENS_MANAGER_ROLE} from "@lattice/ens/libraries/ENSResolverLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IENSResolverV2} from "@lattice/interfaces/ens/IENSResolverV2.sol";
import {IAddrResolver} from "@lattice/interfaces/external/ens/IAddrResolver.sol";
import {IUniversalResolverV2} from "@lattice/interfaces/external/ens/IUniversalResolverV2.sol";

/// @title ENSResolverV2Test
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
contract ENSResolverV2Test is ENSResolverV2TestBase {
    address constant PROXY = address(0x111);
    address constant TARGET = address(0xabc);
    bytes constant NAME = hex"03666f6f0365746800"; // foo.eth
    IENSResolverV2 facet;
    bytes32 node;
    bytes findCall;
    bytes resolveCall;

    function setUp() public {
        vm.etch(PROXY, hex"00");
        vm.mockCall(PROXY, abi.encodeCall(IUniversalResolverV2.isENSv2, ()), abi.encode(true));
        facet = _deployENSResolverV2(address(this), PROXY);
        node = keccak256(abi.encodePacked(keccak256(abi.encodePacked(bytes32(0), keccak256("eth"))), keccak256("foo")));
        findCall = abi.encodeCall(IUniversalResolverV2.findResolver, (NAME));
        resolveCall = abi.encodeCall(IUniversalResolverV2.resolve, (NAME, abi.encodeCall(IAddrResolver.addr, (node))));
        _located(0);
    }

    function _located(uint256 offset) internal {
        vm.mockCall(PROXY, findCall, abi.encode(address(0x234), node, offset));
    }

    function _record(bytes memory value) internal {
        vm.mockCall(PROXY, resolveCall, abi.encode(value, address(0x234)));
    }

    function test_ExactAddress() public {
        _record(abi.encode(TARGET));
        assertEq(facet.resolveEnsAddressV2(NAME), TARGET);
    }

    function test_WildcardRequestsFullNameAndNode() public {
        _located(4);
        _record(abi.encode(TARGET));
        vm.expectCall(PROXY, resolveCall, 1);
        assertEq(facet.resolveEnsAddressV2(NAME), TARGET);
    }

    function test_ZeroRecord() public {
        _record(abi.encode(address(0)));
        assertEq(facet.resolveEnsAddressV2(NAME), address(0));
    }

    function test_MissingResolverPreservesUpstreamError() public {
        vm.mockCall(PROXY, findCall, abi.encode(address(0), node, uint256(0)));
        bytes memory reason = abi.encodeWithSignature("ResolverNotFound(bytes)", NAME);
        vm.mockCallRevert(PROXY, resolveCall, reason);
        vm.expectRevert(reason);
        facet.resolveEnsAddressV2(NAME);
    }

    function test_InvalidNamePreservesUpstreamError() public {
        bytes memory name = hex"08ff";
        bytes memory reason = abi.encodeWithSignature("DNSDecodingFailed(bytes)", name);
        vm.mockCallRevert(PROXY, abi.encodeCall(IUniversalResolverV2.findResolver, (name)), reason);
        vm.expectRevert(reason);
        facet.resolveEnsAddressV2(name);
    }

    function test_InvalidAddressResults() public {
        bytes[] memory invalid = new bytes[](4);
        invalid[0] = bytes("");
        invalid[1] = abi.encodePacked(TARGET);
        invalid[2] = abi.encode(TARGET, TARGET);
        invalid[3] = abi.encode(type(uint256).max);
        for (uint256 i; i < invalid.length; ++i) {
            _record(invalid[i]);
            vm.expectRevert(IENSResolverV2.InvalidENSAddressResult.selector);
            facet.resolveEnsAddressV2(NAME);
        }
    }

    function test_OffchainLookupDuringDiscovery() public {
        _offchain(findCall);
    }

    function test_OffchainLookupDuringResolution() public {
        _offchain(resolveCall);
    }

    function _offchain(bytes memory lookup) internal {
        // Even an upstream error naming the diamond as sender must never escape as a diamond callback.
        bytes memory reason = abi.encodeWithSignature(
            "OffchainLookup(address,string[],bytes,bytes4,bytes)",
            address(facet),
            new string[](0),
            bytes(""),
            bytes4(0),
            bytes("")
        );
        vm.mockCallRevert(PROXY, lookup, reason);
        vm.expectRevert(abi.encodeWithSelector(IENSResolverV2.ENSOffchainLookupRequired.selector, PROXY));
        facet.resolveEnsAddressV2(NAME);
    }

    function test_SupportsInterface() public view {
        assertEq(type(IENSResolverV2).interfaceId, bytes4(0x0e382cd1));
        assertTrue(ERC165Facet(address(facet)).supportsInterface(type(IENSResolverV2).interfaceId));
        assertEq(facet.ensUniversalResolver(), PROXY);
    }

    function test_InitRejectsUnsupportedEndpoint() public {
        address endpoint = address(0xbeef);
        vm.etch(endpoint, hex"00");
        vm.mockCall(endpoint, abi.encodeCall(IUniversalResolverV2.isENSv2, ()), abi.encode(false));
        (FacetCut[] memory cuts, address init, bytes memory data) =
            new DeployENSResolverV2().buildCuts(address(this), endpoint);
        Lattice diamond = new Lattice();
        vm.expectRevert(
            MultiInitErrors.at(
                0, data, abi.encodeWithSelector(IENSResolverV2.InvalidENSUniversalResolver.selector, endpoint)
            )
        );
        diamond.initialize(cuts, init, data);
    }

    function test_RotateRequiresManagerAndValidEndpoint() public {
        address next = address(0x321);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), ENS_MANAGER_ROLE
            )
        );
        facet.setEnsUniversalResolver(next);
        IAccessControl(address(facet)).grantRole(ENS_MANAGER_ROLE, address(this));
        vm.expectRevert(abi.encodeWithSelector(IENSResolverV2.InvalidENSUniversalResolver.selector, next));
        facet.setEnsUniversalResolver(next);
        vm.etch(next, hex"00");
        vm.mockCall(next, abi.encodeCall(IUniversalResolverV2.isENSv2, ()), abi.encode(false));
        vm.expectRevert(abi.encodeWithSelector(IENSResolverV2.InvalidENSUniversalResolver.selector, next));
        facet.setEnsUniversalResolver(next);
        assertEq(facet.ensUniversalResolver(), PROXY);
        vm.mockCall(next, abi.encodeCall(IUniversalResolverV2.isENSv2, ()), abi.encode(true));
        vm.expectEmit(address(facet));
        emit IENSResolverV2.EnsUniversalResolverSet(next);
        facet.setEnsUniversalResolver(next);
        assertEq(facet.ensUniversalResolver(), next);
    }
}
