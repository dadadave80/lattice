// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ENSResolverV2TestBase} from "@lattice-test/base/ENSResolverV2TestBase.sol";
import {IENSResolverV2} from "@lattice/interfaces/ens/IENSResolverV2.sol";
import {IUniversalResolverV2} from "@lattice/interfaces/external/ens/IUniversalResolverV2.sol";

interface IENSMainnetRegistryView {
    function ROOT_REGISTRY() external view returns (address);
    function getSubregistry(string calldata label) external view returns (address);
    function findOwner(string calldata label) external view returns (address);
}

/// @title ENSV2MainnetFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Verifies a native ETH record and a wildcard query through the Lattice facet at block 26,492,000.
/// @dev Block hash 0xdc68292102c2ebbfcbd1f0621183642e381e42df4c4213238dbb32c26737bd34.
///      Registration: https://etherscan.io/tx/0x690a86818b3ea3794892296ae7a916f8e1be0f9ab8e8eac2b482bbc26e9042ad
contract ENSV2MainnetFork is ENSResolverV2TestBase {
    IUniversalResolverV2 constant PROXY = IUniversalResolverV2(0xeEeEEEeE14D718C2B47D9923Deab1335E144EeEe);
    address constant ROOT = 0x2553c09bE6447BeFfdB86FA622ad41fB8f77A91e;
    address constant ETH_REGISTRY = 0xf60aba43E1f7F3DAB1186Ff03B561401C9Df85E2;
    address constant RESOLVER = 0x10865F774e7e6948cD699CEe55e78937da3AAb1d;
    address constant OWNER = 0x69190b7bB503882B139FaBbC0087a27Be4618e6B;
    bytes constant NAME = hex"0d63616d626961736f726973736f0365746800"; // cambiasorisso.eth
    IENSResolverV2 facet;

    function setUp() public {
        if (bytes(vm.envOr("MAINNET_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", 26_492_000);
        assertEq(block.chainid, 1);
        assertTrue(PROXY.isENSv2());
        assertEq(IENSMainnetRegistryView(address(PROXY)).ROOT_REGISTRY(), ROOT);
        assertEq(IENSMainnetRegistryView(ROOT).getSubregistry("eth"), ETH_REGISTRY);
        facet = _deployENSResolverV2(address(this), address(PROXY));
    }

    function test_Fork_NativeRegistrationPointsAtOwner() public view {
        assertEq(IENSMainnetRegistryView(ETH_REGISTRY).findOwner("cambiasorisso"), OWNER);
        (address resolver,, uint256 offset) = PROXY.findResolver(NAME);
        assertEq(resolver, RESOLVER);
        assertEq(offset, 0);
        assertEq(facet.resolveEnsAddressV2(NAME), OWNER);
    }

    function test_Fork_WildcardQueriesChildRecordOnParentResolver() public view {
        bytes memory child = bytes.concat(hex"0570726f6265", NAME); // probe.cambiasorisso.eth
        (address resolver, bytes32 node, uint256 offset) = PROXY.findResolver(child);
        assertEq(resolver, RESOLVER);
        assertEq(offset, 6);
        assertEq(node, 0xe274791661430ca811ae7ae896fccb643d95b10d053d5965ce7673d005c7c782);
        assertEq(facet.resolveEnsAddressV2(child), address(0));
    }
}
