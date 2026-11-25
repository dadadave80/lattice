// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ENS_MANAGER_ROLE} from "@lattice/ens/libraries/ENSResolverLib.sol";
import {IENSResolverV2} from "@lattice/interfaces/ens/IENSResolverV2.sol";
import {IAddrResolver} from "@lattice/interfaces/external/ens/IAddrResolver.sol";
import {IUniversalResolverV2} from "@lattice/interfaces/external/ens/IUniversalResolverV2.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev ERC-7201 root for lattice.storage.ENSResolverV2.
bytes32 constant ENS_RESOLVER_V2_STORAGE_SLOT = 0x3a5b7e307d83c2daef1d3b1c4c22c645e6742b4a2029b8052436497b174f5700;

/// @dev 0x0e382cd1 is `type(IENSResolverV2).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x0e382cd1), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IENSRESOLVERV2_SLOT = 0xaf6f0ce5096406f85a101dad50e1d789075890847130f2e2e506960103b3532a;

/// @custom:storage-location erc7201:lattice.storage.ENSResolverV2
struct ENSResolverV2Storage {
    address _universalResolver;
}

/// @title ENSResolverV2Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS Universal Resolver (https://github.com/ensdomains/contracts-v2)
/// @notice Resolves the addr(bytes32) profile using the complete node from ENSv2 discovery.
library ENSResolverV2Lib {
    bytes4 private constant OFFCHAIN_LOOKUP = bytes4(keccak256("OffchainLookup(address,string[],bytes,bytes4,bytes)"));

    function ensResolverV2Storage() internal pure returns (ENSResolverV2Storage storage $) {
        assembly ("memory-safe") {
            $.slot := ENS_RESOLVER_V2_STORAGE_SLOT
        }
    }

    function __ENSResolverV2_init(address endpoint) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (ensUniversalResolver() != address(0)) revert IENSResolverV2.ENSResolverV2AlreadyInitialized();
        _setEndpoint(endpoint);
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IENSRESOLVERV2_SLOT, true)
        }
    }

    function resolveEnsAddressV2(bytes calldata dnsName) internal view returns (address) {
        address endpoint = ensUniversalResolver();
        bytes memory discovery = _query(endpoint, abi.encodeCall(IUniversalResolverV2.findResolver, (dnsName)));
        (, bytes32 node,) = abi.decode(discovery, (address, bytes32, uint256));
        bytes memory profile = abi.encodeCall(IAddrResolver.addr, (node));
        bytes memory response = _query(endpoint, abi.encodeCall(IUniversalResolverV2.resolve, (dnsName, profile)));
        (bytes memory record,) = abi.decode(response, (bytes, address));
        if (record.length != 32 || uint256(bytes32(record)) > type(uint160).max) {
            revert IENSResolverV2.InvalidENSAddressResult();
        }
        return abi.decode(record, (address));
    }

    /// @dev ERC-3668 callbacks belong to the endpoint. A diamond must not pass them off as its own.
    function _query(address endpoint, bytes memory data) private view returns (bytes memory result) {
        bool success;
        (success, result) = endpoint.staticcall(data);
        if (!success) {
            if (bytes4(result) == OFFCHAIN_LOOKUP) revert IENSResolverV2.ENSOffchainLookupRequired(endpoint);
            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    function ensUniversalResolver() internal view returns (address) {
        return ensResolverV2Storage()._universalResolver;
    }

    function setEnsUniversalResolver(address endpoint) internal {
        AccessControlLib.checkRole(ENS_MANAGER_ROLE);
        if (ensUniversalResolver() == address(0)) revert IENSResolverV2.ENSResolverV2NotInitialized();
        _setEndpoint(endpoint);
    }

    function _setEndpoint(address endpoint) private {
        if (endpoint.code.length == 0) revert IENSResolverV2.InvalidENSUniversalResolver(endpoint);
        (bool ok, bytes memory version) = endpoint.staticcall(abi.encodeCall(IUniversalResolverV2.isENSv2, ()));
        if (!ok || version.length != 32 || uint256(bytes32(version)) != 1) {
            revert IENSResolverV2.InvalidENSUniversalResolver(endpoint);
        }
        ensResolverV2Storage()._universalResolver = endpoint;
        emit IENSResolverV2.EnsUniversalResolverSet(endpoint);
    }
}
