// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {AxelarGatewayAdapterLib} from "@lattice/crosschain/axelar/AxelarGatewayAdapterLib.sol";
import {CCIPGatewayAdapterLib} from "@lattice/crosschain/chainlink/CCIPGatewayAdapterLib.sol";
import {CCTPBridgeAdapterLib} from "@lattice/crosschain/circle/CCTPBridgeAdapterLib.sol";
import {HyperbridgeGatewayAdapterLib} from "@lattice/crosschain/hyperbridge/HyperbridgeGatewayAdapterLib.sol";
import {HyperlaneGatewayAdapterLib} from "@lattice/crosschain/hyperlane/HyperlaneGatewayAdapterLib.sol";
import {LayerZeroGatewayAdapterLib} from "@lattice/crosschain/layerzero/LayerZeroGatewayAdapterLib.sol";
import {StargateBridgeAdapterLib} from "@lattice/crosschain/layerzero/StargateBridgeAdapterLib.sol";
import {
    L2ToL2CrossDomainMessengerGatewayAdapterLib
} from "@lattice/crosschain/optimism/L2ToL2CrossDomainMessengerGatewayAdapterLib.sol";
import {WormholeGatewayAdapterLib} from "@lattice/crosschain/wormhole/WormholeGatewayAdapterLib.sol";
import {ZetaChainGatewayAdapterLib} from "@lattice/crosschain/zetachain/ZetaChainGatewayAdapterLib.sol";
import {IChainRegistry} from "@lattice/interfaces/crosschain/IChainRegistry.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ChainRegistry")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CHAIN_REGISTRY_STORAGE_SLOT = 0x3d04730f387c3a41671abdc91e43582ee4d80e460792f9c401b5acc80eab5b00;

/// @dev 0x137e339e is `type(IChainRegistry).interfaceId` (changed when `HyperbridgeSection` was appended to
/// `AddEvmChainConfig` — the struct rides in the `addEvmChain` signature).
/// `keccak256(abi.encode(bytes4(0x137e339e), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICHAINREGISTRY_SLOT = 0x0a0affa1c3cd17b5e25d35fd719de9756671b9a056876933fee65c04fc5735d3;

/// @notice Per-chain registry record, keyed by the ERC-7930 chain key. APPEND-ONLY.
struct ChainRecord {
    /// @notice Whether this chain identity is registered (identities are permanent — no removal in v1).
    bool registered;
    /// @notice The ERC-7930 chain type (0x0000 = eip-155).
    bytes2 chainType;
    /// @notice The ERC-7930 chain reference (canonical minimal big-endian chainId for EVM chains).
    bytes chainReference;
    /// @notice The EVM chainId (informational; 0 for non-EVM chains).
    uint256 evmChainId;
    /// @notice Informational native bridge-ecosystem ids (0/empty = unset).
    IChainRegistry.NativeIds ids;
    /// @notice The local gateway adapters recorded as covering this chain (direct + hub-routed).
    EnumerableSet.AddressSet gateways;
    /// @notice gateway => reaches this chain only via an intermediate hub (never counts as DIRECT coverage).
    mapping(address gateway => bool hubRouted) hubRouted;
}

/// @notice ERC-7201 namespaced storage for the chain registry.
/// @custom:storage-location erc7201:lattice.storage.ChainRegistry
struct ChainRegistryStorage {
    /// @notice chainKey (`keccak256(abi.encodePacked(chainType, chainReference))`) => record. APPEND-ONLY.
    mapping(bytes32 chainKey => ChainRecord record) _chains;
}

/// @title ChainRegistryLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic + ERC-7201 storage for the Lattice chain registry: chain identities keyed by
///         `keccak256(abi.encodePacked(chainType, chainReference))` (EVM and non-EVM handled identically), an
///         informational native-id index, per-chain gateway coverage with direct/hub-routed distinction, and
///         {addEvmChain} — the one-action admin fan-out that registers an EVM chain and pushes its config into
///         every enabled gateway adapter LIB directly (internal calls, so `msg.sender` stays the admin and each
///         lib's own `checkRole` passes; NEVER external self-calls, which would break AccessControl).
/// @dev COVERAGE AWARENESS, NOT ROUTING (issue #77 Q5): the registry is the config single-source-of-truth and
///      the coverage authority, but adapters keep their own cheap hot-path maps — the registry NEVER sits in
///      any adapter send path (the only cross-module reader is the OpenBridge's opt-in
///      `minDirectCoverage` gate). Hub-routed coverage (e.g. the ZetaChain adapter reaching connected chains
///      only via the ZEVM hub) NEVER counts toward {directCoverageOf}.
library ChainRegistryLib {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev The ERC-7930 chain type of eip-155 (EVM) chains.
    bytes2 internal constant EVM_CHAIN_TYPE = 0x0000;

    function chainRegistryStorage() internal pure returns (ChainRegistryStorage storage $) {
        assembly {
            $.slot := CHAIN_REGISTRY_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IChainRegistry ERC-165 id. Called inside the diamond initializing window.
    function __ChainRegistry_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for `IChainRegistry`.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ICHAINREGISTRY_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                CHAIN KEYS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The chain key of any ERC-7930 chain identity.
    function chainKeyOf(bytes2 chainType, bytes memory chainReference) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(chainType, chainReference));
    }

    /// @notice The chain key of an EVM chain (eip-155 chainType + canonical minimal big-endian reference).
    function chainKeyEvm(uint256 chainId) internal pure returns (bytes32) {
        return chainKeyOf(EVM_CHAIN_TYPE, _evmChainReference(chainId));
    }

    /// @notice The canonical minimal big-endian (no leading zeros) ERC-7930 chain reference of `chainId`.
    /// @dev Derived by round-tripping {InteroperableAddress.formatEvmV1} through {InteroperableAddress.parseV1}
    ///      — the ONE encoding the whole repo uses; deliberately not re-implemented here.
    function _evmChainReference(uint256 chainId) private pure returns (bytes memory chainReference) {
        (, chainReference,) = InteroperableAddress.parseV1(InteroperableAddress.formatEvmV1(chainId));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function isRegistered(bytes32 chainKey) internal view returns (bool) {
        return chainRegistryStorage()._chains[chainKey].registered;
    }

    function chainInfoOf(bytes32 chainKey)
        internal
        view
        returns (bytes2 chainType, bytes memory chainReference, uint256 evmChainId)
    {
        ChainRecord storage record = chainRegistryStorage()._chains[chainKey];
        return (record.chainType, record.chainReference, record.evmChainId);
    }

    function nativeIdsOf(bytes32 chainKey) internal view returns (IChainRegistry.NativeIds memory) {
        return chainRegistryStorage()._chains[chainKey].ids;
    }

    function gatewaysOf(bytes32 chainKey) internal view returns (address[] memory) {
        return chainRegistryStorage()._chains[chainKey].gateways.values();
    }

    /// @notice The total number of gateways covering `chainKey` (direct + hub-routed).
    function coverageOf(bytes32 chainKey) internal view returns (uint256) {
        return chainRegistryStorage()._chains[chainKey].gateways.length();
    }

    /// @notice The number of gateways covering `chainKey` DIRECTLY — hub-routed coverage never counts.
    /// @dev O(n) over the coverage set; n is admin-bounded small (at most one entry per local adapter).
    function directCoverageOf(bytes32 chainKey) internal view returns (uint256 direct) {
        ChainRecord storage record = chainRegistryStorage()._chains[chainKey];
        uint256 total = record.gateways.length();
        for (uint256 i; i < total; ++i) {
            if (!record.hubRouted[record.gateways.at(i)]) ++direct;
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers a chain identity (EVM or non-EVM). Admin only. Re-register reverts
    ///         {ChainRegistryAlreadyRegistered} — chain identities are permanent, so an explicit `removeChain`
    ///         is deliberately absent in v1 (YAGNI; coverage entries and native ids stay mutable).
    function registerChain(bytes2 chainType, bytes calldata chainReference, uint256 evmChainId) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _registerChain(chainType, chainReference, evmChainId);
    }

    /// @notice Sets the informational native ids of a registered chain. Admin only.
    function setNativeIds(bytes32 chainKey, IChainRegistry.NativeIds calldata ids) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setNativeIds(chainKey, ids);
    }

    /// @notice Records (`covered = true`, with the given `hubRouted` flag) or clears (`covered = false`)
    ///         `gateway`'s coverage of a registered chain. Admin only. Re-recording an existing gateway
    ///         updates its `hubRouted` flag.
    function setGatewayCoverage(bytes32 chainKey, address gateway, bool covered, bool hubRouted) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setGatewayCoverage(chainKey, gateway, covered, hubRouted);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ADD-CHAIN FAN-OUT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ONE structured admin action that adds an EVM chain everywhere: registers the chain identity,
    ///         records the native ids declared by the enabled sections, fans the per-adapter config out into
    ///         every ENABLED adapter lib (direct internal calls — `msg.sender` stays the admin, so each lib's
    ///         own `DEFAULT_ADMIN_ROLE` check passes), then records the coverage entries. Admin only.
    /// @dev The fan-out writes each enabled adapter's ERC-7201 slots whether or not that adapter's facet is
    ///      cut into this diamond — un-hosted slots simply go unread until such a facet is cut, so leaving a
    ///      section for an un-hosted adapter disabled is the ADMIN's responsibility (no facet-existence
    ///      introspection by design). Per-adapter duplicate guards (e.g. `ChainSelectorAlreadyRegistered`)
    ///      bubble up unchanged and roll back the whole action.
    function addEvmChain(IChainRegistry.AddEvmChainConfig calldata cfg) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);

        // 1) Register the chain identity: eip-155 + the canonical minimal big-endian reference.
        bytes32 chainKey = _registerChain(EVM_CHAIN_TYPE, _evmChainReference(cfg.chainId), cfg.chainId);

        // 2) Record the informational native ids declared by the ENABLED sections (disabled = unset).
        IChainRegistry.NativeIds memory ids;
        if (cfg.ccip.enabled) ids.ccipSelector = cfg.ccip.selector;
        if (cfg.layerZero.enabled) ids.lzEid = cfg.layerZero.eid;
        if (cfg.wormhole.enabled) ids.wormholeId = cfg.wormhole.wormholeId;
        if (cfg.cctp.enabled) ids.cctpDomain = cfg.cctp.domain;
        if (cfg.axelar.enabled) ids.axelarName = cfg.axelar.axelarName;
        if (cfg.hyperlane.enabled) ids.hyperlaneDomain = cfg.hyperlane.domain;
        _setNativeIds(chainKey, ids);

        // 3) Fan out into every enabled adapter lib's own ERC-7201 storage (internal admin writes only).
        if (cfg.ccip.enabled) {
            CCIPGatewayAdapterLib.registerChainSelector(cfg.chainId, cfg.ccip.selector);
            CCIPGatewayAdapterLib.registerRemoteGateway(cfg.chainId, cfg.ccip.remoteGateway);
            CCIPGatewayAdapterLib.configureDestination(
                cfg.chainId, cfg.ccip.gasLimit, cfg.ccip.allowOutOfOrderExecution
            );
        }
        if (cfg.layerZero.enabled) {
            LayerZeroGatewayAdapterLib.registerEid(cfg.chainId, cfg.layerZero.eid);
            LayerZeroGatewayAdapterLib.registerPeer(cfg.chainId, cfg.layerZero.peer);
            LayerZeroGatewayAdapterLib.configureDestination(cfg.chainId, cfg.layerZero.gas, cfg.layerZero.msgValue);
        }
        if (cfg.wormhole.enabled) {
            WormholeGatewayAdapterLib.registerChainEquivalence(cfg.chainId, cfg.wormhole.wormholeId);
            WormholeGatewayAdapterLib.registerRemoteGateway(cfg.chainId, cfg.wormhole.remote);
        }
        if (cfg.axelar.enabled) {
            _checkAxelarSection(cfg.chainId, cfg.axelar);
            AxelarGatewayAdapterLib.registerChainEquivalence(cfg.axelar.chain7930, cfg.axelar.axelarName);
            AxelarGatewayAdapterLib.registerRemoteGateway(cfg.axelar.remote7930);
        }
        if (cfg.zeta.enabled) {
            ZetaChainGatewayAdapterLib.registerRemote(cfg.chainId, cfg.zeta.remoteApp);
        }
        if (cfg.opL2ToL2.enabled) {
            L2ToL2CrossDomainMessengerGatewayAdapterLib.registerRemoteAdapter(cfg.chainId, cfg.opL2ToL2.remoteAdapter);
        }
        if (cfg.cctp.enabled) {
            CCTPBridgeAdapterLib.registerChainDomain(cfg.chainId, cfg.cctp.domain);
            CCTPBridgeAdapterLib.configureDomain(
                cfg.cctp.domain, cfg.cctp.maxFee, cfg.cctp.minFinalityThreshold, cfg.cctp.destinationCaller
            );
        }
        if (cfg.hyperlane.enabled) {
            HyperlaneGatewayAdapterLib.registerDomain(cfg.chainId, cfg.hyperlane.domain);
            HyperlaneGatewayAdapterLib.registerRemote(cfg.chainId, cfg.hyperlane.remote);
            HyperlaneGatewayAdapterLib.configureDestination(cfg.chainId, cfg.hyperlane.gasLimit);
        }
        // Stargate rides LayerZero: the section's eid equals the LZ section's eid, recorded in the Stargate
        // adapter's OWN map (no NativeIds field — `NativeIds.lzEid` is the informational record; per-token
        // pools are registered separately via `registerPool`, never through the fan-out).
        if (cfg.stargate.enabled) {
            // FAIL-CLOSED cross-check (review finding): when both sections are enabled the two eids MUST agree
            // — a typoed Stargate eid would silently route user funds to the WRONG chain on every later
            // sendToken. When layerZero is disabled no cross-check is possible (residual admin trust).
            if (cfg.layerZero.enabled && cfg.stargate.eid != cfg.layerZero.eid) {
                revert IChainRegistry.ChainRegistryStargateEidMismatch(cfg.layerZero.eid, cfg.stargate.eid);
            }
            StargateBridgeAdapterLib.registerStargateEid(cfg.chainId, cfg.stargate.eid);
        }
        // Hyperbridge routes by BYTES state machine ids DERIVED from the chainId (`bytes("EVM-" + chainId)`)
        // — the section carries no id, so a typoed id can never misroute (fail-closed by construction). The
        // derived id is not recorded in NativeIds: it is a pure function of the chainId.
        if (cfg.hyperbridge.enabled) {
            HyperbridgeGatewayAdapterLib.registerStateMachine(cfg.chainId);
            HyperbridgeGatewayAdapterLib.registerRemoteModule(cfg.chainId, cfg.hyperbridge.remoteModule);
            HyperbridgeGatewayAdapterLib.configureDestinationTimeout(cfg.chainId, cfg.hyperbridge.timeout);
        }

        // 4) Record the coverage entries (parallel arrays, length-checked).
        uint256 covered = cfg.coverage.gateways.length;
        if (covered != cfg.coverage.hubRouted.length) {
            revert IChainRegistry.ChainRegistryCoverageLengthMismatch(covered, cfg.coverage.hubRouted.length);
        }
        for (uint256 i; i < covered; ++i) {
            _setGatewayCoverage(chainKey, cfg.coverage.gateways[i], true, cfg.coverage.hubRouted[i]);
        }

        emit IChainRegistry.ChainAdded(chainKey, cfg.chainId);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the chain identity and returns its key. Reverts {ChainRegistryEmptyChainReference} on
    ///         an empty reference, {ChainRegistryAlreadyRegistered} if the identity already exists.
    /// @dev FAIL-CLOSED eip-155 canonicality (review finding): an EVM chainType requires a non-zero
    ///      `evmChainId` whose canonical minimal-big-endian reference byte-equals `chainReference` — a
    ///      non-minimal reference (e.g. hex"000a" for chain 10) would mint a chainKey the send-time derivation
    ///      can NEVER match, silently making coverage records unreachable. Non-EVM chainTypes require
    ///      `evmChainId == 0` (the field is meaningless there).
    function _registerChain(bytes2 chainType, bytes memory chainReference, uint256 evmChainId)
        private
        returns (bytes32 chainKey)
    {
        if (chainReference.length == 0) revert IChainRegistry.ChainRegistryEmptyChainReference();
        if (chainType == EVM_CHAIN_TYPE) {
            if (evmChainId == 0 || keccak256(chainReference) != keccak256(_evmChainReference(evmChainId))) {
                revert IChainRegistry.ChainRegistryNonCanonicalEvmReference(chainReference, evmChainId);
            }
        } else if (evmChainId != 0) {
            revert IChainRegistry.ChainRegistryEvmChainIdOnNonEvmChain(evmChainId);
        }
        chainKey = chainKeyOf(chainType, chainReference);
        ChainRecord storage record = chainRegistryStorage()._chains[chainKey];
        if (record.registered) revert IChainRegistry.ChainRegistryAlreadyRegistered(chainKey);
        record.registered = true;
        record.chainType = chainType;
        record.chainReference = chainReference;
        record.evmChainId = evmChainId;
        emit IChainRegistry.ChainRegistered(chainKey, chainType, chainReference, evmChainId);
    }

    function _setNativeIds(bytes32 chainKey, IChainRegistry.NativeIds memory ids) private {
        _registeredRecord(chainKey).ids = ids;
        emit IChainRegistry.SetNativeIds(chainKey, ids);
    }

    /// @dev EVENT FIDELITY (review finding): the emitted event mirrors STORED state exactly so off-chain
    ///      indexers reconstructing coverage from events cannot drift — a no-op removal (gateway was never
    ///      covered) emits nothing, and the covered=false path always logs hubRouted=false (the flag is
    ///      deleted, never stored).
    function _setGatewayCoverage(bytes32 chainKey, address gateway, bool covered, bool hubRouted) private {
        if (gateway == address(0)) revert IChainRegistry.ChainRegistryZeroGateway();
        ChainRecord storage record = _registeredRecord(chainKey);
        if (covered) {
            record.gateways.add(gateway);
            record.hubRouted[gateway] = hubRouted;
            emit IChainRegistry.SetGatewayCoverage(chainKey, gateway, true, hubRouted);
        } else if (record.gateways.remove(gateway)) {
            delete record.hubRouted[gateway];
            emit IChainRegistry.SetGatewayCoverage(chainKey, gateway, false, false);
        }
    }

    /// @notice The record of `chainKey`, reverting {ChainRegistryNotRegistered} when it is not registered.
    function _registeredRecord(bytes32 chainKey) private view returns (ChainRecord storage record) {
        record = chainRegistryStorage()._chains[chainKey];
        if (!record.registered) revert IChainRegistry.ChainRegistryNotRegistered(chainKey);
    }

    /// @notice Fail-closed Axelar section checks: `chain7930` must be the CANONICAL chain-only ERC-7930
    ///         address of `chainId` (the exact bytes the Axelar adapter keys its equivalence map with —
    ///         `InteroperableAddress.formatEvmV1(chainId)`), and `remote7930` must address `chainId`.
    function _checkAxelarSection(uint256 chainId, IChainRegistry.AxelarSection calldata section) private pure {
        if (keccak256(section.chain7930) != keccak256(InteroperableAddress.formatEvmV1(chainId))) {
            revert IChainRegistry.ChainRegistryAxelarChainMismatch();
        }
        (uint256 remoteChainId,) = InteroperableAddress.parseEvmV1Calldata(section.remote7930);
        if (remoteChainId != chainId) revert IChainRegistry.ChainRegistryAxelarRemoteMismatch();
    }
}
