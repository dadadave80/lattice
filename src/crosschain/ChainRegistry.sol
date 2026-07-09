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
///      in the admin write paths of all ten adapter libs (CCIP, LayerZero, Wormhole, Axelar, ZetaChain,
///      OP L2-to-L2, CCTP, Hyperlane, Stargate, Hyperbridge) as INTERNAL calls only. A diamond that cuts
///      ChainRegistry without some adapter
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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ChainRegistry methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `addEvmChain((uint256,(bool,uint64,address,uint256,bool),(bool,uint32,bytes32,uint128,uint128),(bool,uint16,address),(bool,string,bytes,bytes),(bool,address),(bool,address),(bool,uint32,uint256,uint32,bytes32),(bool,uint32,bytes32,uint256),(bool,uint32),(bool,bytes,uint64),(address[],bool[])))` 0xdae1aa2e
    ///      `chainInfoOf(bytes32)` 0x6a419425
    ///      `chainKeyEvm(uint256)` 0x585f36e8
    ///      `chainKeyOf(bytes2,bytes)` 0xa0f8fb2f
    ///      `coverageOf(bytes32)` 0xeede78f6
    ///      `directCoverageOf(bytes32)` 0xbcf041b6
    ///      `gatewaysOf(bytes32)` 0xa61e0052
    ///      `isRegistered(bytes32)` 0x27258b22
    ///      `nativeIdsOf(bytes32)` 0x281a6e02
    ///      `registerChain(bytes2,bytes,uint256)` 0x6f4cb737
    ///      `setGatewayCoverage(bytes32,address,bool,bool)` 0x6688921d
    ///      `setNativeIds(bytes32,(uint64,uint32,uint16,uint32,string,uint32))` 0xa9b2394a
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
        hex"dae1aa2e6a419425585f36e8a0f8fb2feede78f6bcf041b6a61e005227258b22281a6e026f4cb7376688921da9b2394a";
    }
}
