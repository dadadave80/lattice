// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ENSResolverLib} from "@lattice/ens/libraries/ENSResolverLib.sol";
import {IENSResolver} from "@lattice/interfaces/ens/IENSResolver.sol";

/// @title ENSResolver
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS (https://github.com/ensdomains/ens-contracts)
/// @author Conforms to ENS forward resolution (EIP-137)
/// @notice Stateless Diamond facet for on-chain ENS forward resolution: resolves an ENS node to its
///         address via the configured ENS registry.
/// @dev All logic lives in {ENSResolverLib}. The ENS registry is supplied at init and rotated per chain
///      via {setEnsRegistry} (gated on `ENS_MANAGER_ROLE`, managed through the diamond's AccessControl).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract ENSResolver is IENSResolver {
    /// @inheritdoc IENSResolver
    function resolve(bytes32 node) external view virtual returns (address) {
        return ENSResolverLib.resolve(node);
    }

    /// @inheritdoc IENSResolver
    function resolverOf(bytes32 node) external view virtual returns (address) {
        return ENSResolverLib.resolverOf(node);
    }

    /// @inheritdoc IENSResolver
    function ensRegistry() external view virtual returns (address) {
        return ENSResolverLib.ensRegistry();
    }

    /// @inheritdoc IENSResolver
    function setEnsRegistry(address ensRegistry_) external virtual {
        ENSResolverLib.setEnsRegistry(ensRegistry_);
    }

    /// @inheritdoc IENSResolver
    function subnode(bytes32 parentNode, string calldata label) external pure virtual returns (bytes32) {
        return ENSResolverLib.subnode(parentNode, label);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ENSResolver methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `ensRegistry()` 0x7d73b231
    ///      `resolve(bytes32)` 0x5c23bdf5
    ///      `resolverOf(bytes32)` 0xc677966d
    ///      `setEnsRegistry(address)` 0xe7c65687
    ///      `subnode(bytes32,string)` 0x568f0953
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"7d73b2315c23bdf5c677966de7c65687568f0953";
    }
}
