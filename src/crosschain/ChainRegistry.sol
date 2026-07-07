// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ChainRegistryLib} from "@lattice/crosschain/libraries/ChainRegistryLib.sol";
import {IChainRegistry} from "@lattice/interfaces/crosschain/IChainRegistry.sol";

/// @title ChainRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Chain-registry facet: a generic registry of chain identities keyed by the ERC-7930 chain key,
///         per-chain native bridge-ecosystem ids, gateway coverage awareness (direct vs hub-routed), and
///         {addEvmChain} — the one-action admin fan-out that adds an EVM chain across every enabled gateway
///         adapter in a single structured call.
/// @dev Stateless delegator — logic/storage live in {ChainRegistryLib}. FAN-OUT COUPLING: this facet compiles
///      in the admin write paths of all seven adapter libs (CCIP, LayerZero, Wormhole, Axelar, ZetaChain,
///      OP L2-to-L2, CCTP) as INTERNAL calls only. A diamond that cuts ChainRegistry without some adapter
///      facet still works — the libs write to ERC-7201 slots that simply go unread until that facet is cut;
///      leaving a section for an un-hosted adapter disabled is the admin's responsibility (see
///      {IChainRegistry.AddEvmChainConfig}).
/// @custom:lattice-version 0.1.0
contract ChainRegistry is IChainRegistry {
    /// @inheritdoc IChainRegistry
    function chainKeyEvm(uint256 chainId) external pure virtual returns (bytes32) {
        return ChainRegistryLib.chainKeyEvm(chainId);
    }

    /// @inheritdoc IChainRegistry
    function chainKeyOf(bytes2 chainType, bytes calldata chainReference) external pure virtual returns (bytes32) {
        return ChainRegistryLib.chainKeyOf(chainType, chainReference);
    }

    /// @inheritdoc IChainRegistry
    function isRegistered(bytes32 chainKey) external view virtual returns (bool) {
        return ChainRegistryLib.isRegistered(chainKey);
    }

    /// @inheritdoc IChainRegistry
    function chainInfoOf(bytes32 chainKey)
        external
        view
        virtual
        returns (bytes2 chainType, bytes memory chainReference, uint256 evmChainId)
    {
        return ChainRegistryLib.chainInfoOf(chainKey);
    }

    /// @inheritdoc IChainRegistry
    function nativeIdsOf(bytes32 chainKey) external view virtual returns (NativeIds memory) {
        return ChainRegistryLib.nativeIdsOf(chainKey);
    }

    /// @inheritdoc IChainRegistry
    function gatewaysOf(bytes32 chainKey) external view virtual returns (address[] memory) {
        return ChainRegistryLib.gatewaysOf(chainKey);
    }

    /// @inheritdoc IChainRegistry
    function coverageOf(bytes32 chainKey) external view virtual returns (uint256) {
        return ChainRegistryLib.coverageOf(chainKey);
    }

    /// @inheritdoc IChainRegistry
    function directCoverageOf(bytes32 chainKey) external view virtual returns (uint256) {
        return ChainRegistryLib.directCoverageOf(chainKey);
    }

    /// @inheritdoc IChainRegistry
    function registerChain(bytes2 chainType, bytes calldata chainReference, uint256 evmChainId) external virtual {
        ChainRegistryLib.registerChain(chainType, chainReference, evmChainId);
    }

    /// @inheritdoc IChainRegistry
    function setNativeIds(bytes32 chainKey, NativeIds calldata ids) external virtual {
        ChainRegistryLib.setNativeIds(chainKey, ids);
    }

    /// @inheritdoc IChainRegistry
    function setGatewayCoverage(bytes32 chainKey, address gateway, bool covered, bool hubRouted) external virtual {
        ChainRegistryLib.setGatewayCoverage(chainKey, gateway, covered, hubRouted);
    }

    /// @inheritdoc IChainRegistry
    function addEvmChain(AddEvmChainConfig calldata cfg) external virtual {
        ChainRegistryLib.addEvmChain(cfg);
    }
}
