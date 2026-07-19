// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IENSResolver} from "@lattice/interfaces/ens/IENSResolver.sol";
import {IAddrResolver} from "@lattice/interfaces/external/ens/IAddrResolver.sol";
import {IENS} from "@lattice/interfaces/external/ens/IENS.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ENSResolver")) - 1)) & ~bytes32(uint256(0xff))`.
///      Verify with: `cast index-erc7201 "lattice.storage.ENSResolver"`.
bytes32 constant ENS_RESOLVER_STORAGE_SLOT = 0x33f26d8db6499021a25127a427a9f060956987880daa3f7db97807f377225300;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ENS_RESOLVER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x566ec67d is `type(IENSResolver).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x566ec67d), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IENSRESOLVER_SLOT = 0x79535b2b28365a4b28deff1d36dfc239871172c80dcc5e494674d846366975cb;

/// @dev Role allowed to manage the diamond's ENS configuration. Uses the value
///      `keccak256("ENS_MANAGER_ROLE")`, intended to be shared with future ENS identity modules.
bytes32 constant ENS_MANAGER_ROLE = keccak256("ENS_MANAGER_ROLE");

/// @notice ERC-7201 namespaced storage for the ENSResolver module.
/// @dev APPEND-ONLY: new fields may only be added at the end to preserve the upgrade-safe layout.
/// @custom:storage-location erc7201:lattice.storage.ENSResolver
struct ENSResolverStorage {
    /// @dev The ENS registry used for forward resolution.
    address _ensRegistry;
}

/// @title ENSResolverLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS (https://github.com/ensdomains/ens-contracts)
/// @notice Library for on-chain ENS forward resolution: looks up an ENS node's resolver in the
///         configured registry and reads its `addr` record.
/// @dev Three-layer pattern: this library holds the logic and namespaced storage; the stateless
///      {ENSResolver} facet forwards to it. Basic resolution only (registry -> resolver -> addr);
///      ENSIP-10 wildcard / extended resolution is out of scope for v1.
library ENSResolverLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function ensResolverStorage() internal pure returns (ENSResolverStorage storage $) {
        assembly {
            $.slot := ENS_RESOLVER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ENSResolver module with the ENS registry to use.
    /// @dev Must be called inside a pre/postInitializer block. Reverts {ENSResolverZeroRegistry} for a
    ///      zero registry. Registers IENSResolver for ERC-165 discovery.
    /// @param _ensRegistry The ENS registry for this chain.
    function __ENSResolver_init(address _ensRegistry) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        if (_ensRegistry == address(0)) revert IENSResolver.ENSResolverZeroRegistry();
        ensResolverStorage()._ensRegistry = _ensRegistry;
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IENSResolver interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IENSRESOLVER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             FORWARD RESOLUTION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Resolves an ENS `node` to its address.
    /// @dev Returns zero ONLY when `node` has no resolver configured. MAY revert (bubbling the
    ///      resolver's revert) if a configured resolver does not implement `addr(bytes32)` or itself
    ///      reverts. The resolved address is set by the node's owner (a third party) — treat it as
    ///      untrusted; use {resolverOf} to distinguish "no resolver" from "resolves to zero".
    /// @param node The ENS node (namehash) to resolve.
    /// @return The resolved address (zero if no resolver is set).
    function resolve(bytes32 node) internal view returns (address) {
        address nodeResolver = IENS(ensResolverStorage()._ensRegistry).resolver(node);
        if (nodeResolver == address(0)) return address(0);
        return IAddrResolver(nodeResolver).addr(node);
    }

    /// @notice Returns the resolver configured for `node` in the ENS registry.
    /// @param node The ENS node (namehash) to query.
    /// @return The resolver address (zero if unset).
    function resolverOf(bytes32 node) internal view returns (address) {
        return IENS(ensResolverStorage()._ensRegistry).resolver(node);
    }

    /// @notice Computes the namehash of `label`.<parent> (one ENS namehash recursion step).
    /// @param parentNode The parent name's node.
    /// @param label The subname label.
    /// @return The child node (namehash).
    function subnode(bytes32 parentNode, string calldata label) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(parentNode, keccak256(bytes(label))));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              CONFIGURATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets or rotates the ENS registry.
    /// @dev Gated on `ENS_MANAGER_ROLE`. Reverts {ENSResolverZeroRegistry} for a zero address.
    /// @param _ensRegistry The ENS registry to use.
    function setEnsRegistry(address _ensRegistry) internal {
        AccessControlLib.checkRole(ENS_MANAGER_ROLE);
        if (_ensRegistry == address(0)) revert IENSResolver.ENSResolverZeroRegistry();
        ensResolverStorage()._ensRegistry = _ensRegistry;
        emit IENSResolver.EnsRegistrySet(_ensRegistry);
    }

    /// @notice Returns the configured ENS registry.
    function ensRegistry() internal view returns (address) {
        return ensResolverStorage()._ensRegistry;
    }
}
