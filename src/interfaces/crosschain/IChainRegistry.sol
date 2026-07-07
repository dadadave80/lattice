// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IChainRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Admin / read surface of the Lattice chain registry: a generic ERC-7201 registry of chains keyed by
///         their ERC-7930 chain identity (`chainKey = keccak256(abi.encodePacked(chainType, chainReference))`,
///         so EVM and non-EVM chains are supported identically), an informational native-id index per bridge
///         ecosystem, a per-chain gateway COVERAGE map (which local gateway adapters can reach the chain, and
///         whether only via an intermediate hub), and {addEvmChain} — the one-action admin fan-out that
///         registers an EVM chain and pushes its config into every enabled gateway adapter in a single call.
/// @dev COVERAGE AWARENESS, NOT ROUTING (issue #77 Q5): the registry is the config single-source-of-truth and
///      the authority for M-of-N coverage math, but every adapter keeps its own cheap hot-path maps — the
///      registry NEVER sits in any adapter send path. Enforcement is opt-in on the OpenBridge side
///      (`setMinDirectCoverage`); hub-routed coverage (e.g. ZetaChain reaching connected chains only via the
///      ZEVM hub) NEVER counts toward DIRECT coverage. Chains cannot be removed in v1 (YAGNI — a chain identity
///      is permanent; coverage entries and native ids stay mutable).
interface IChainRegistry {
    // -------------------------------------------------------------------------
    //                                  Structs
    // -------------------------------------------------------------------------

    /// @notice Per-chain native identifiers of the major bridge ecosystems. Purely an INFORMATIONAL indexing
    ///         layer (0 / empty = unset) — adapters keep their own authoritative hot-path maps.
    struct NativeIds {
        /// @notice Chainlink CCIP chain selector (0 = unset).
        uint64 ccipSelector;
        /// @notice LayerZero v2 endpoint id (0 = unset).
        uint32 lzEid;
        /// @notice Wormhole chain id (0 = unset).
        uint16 wormholeId;
        /// @notice Circle CCTP domain (0 = unset; NOTE domain 0 is Ethereum — rely on the CCTP adapter's own
        ///         registered flag for authoritative reads, this field is informational).
        uint32 cctpDomain;
        /// @notice Axelar chain name (empty = unset).
        string axelarName;
        /// @notice Hyperlane domain (0 = unset; usually — but NOT guaranteed — the EVM chainId). APPENDED.
        uint32 hyperlaneDomain;
    }

    /// @notice CCIP fan-out section of {AddEvmChainConfig} (disabled sections are skipped entirely).
    struct CcipSection {
        bool enabled;
        uint64 selector;
        address remoteGateway;
        uint256 gasLimit;
        bool allowOutOfOrderExecution;
    }

    /// @notice LayerZero v2 fan-out section of {AddEvmChainConfig}.
    struct LayerZeroSection {
        bool enabled;
        uint32 eid;
        bytes32 peer;
        uint128 gas;
        uint128 msgValue;
    }

    /// @notice Wormhole fan-out section of {AddEvmChainConfig}.
    struct WormholeSection {
        bool enabled;
        uint16 wormholeId;
        address remote;
    }

    /// @notice Axelar fan-out section of {AddEvmChainConfig}. `chain7930` MUST be the canonical chain-only
    ///         ERC-7930 address of the chain being added (`InteroperableAddress.formatEvmV1(chainId)` — the
    ///         exact bytes the Axelar adapter keys its equivalence map with) and `remote7930` the full ERC-7930
    ///         address of the remote gateway ON that chain; both are validated against `chainId`.
    struct AxelarSection {
        bool enabled;
        string axelarName;
        bytes remote7930;
        bytes chain7930;
    }

    /// @notice ZetaChain fan-out section of {AddEvmChainConfig} (`remoteApp` is the ZEVM universal app).
    struct ZetaSection {
        bool enabled;
        address remoteApp;
    }

    /// @notice OP Superchain L2-to-L2 fan-out section of {AddEvmChainConfig}.
    struct OpL2ToL2Section {
        bool enabled;
        address remoteAdapter;
    }

    /// @notice Circle CCTP fan-out section of {AddEvmChainConfig}.
    struct CctpSection {
        bool enabled;
        uint32 domain;
        uint256 maxFee;
        uint32 minFinalityThreshold;
        bytes32 destinationCaller;
    }

    /// @notice Hyperlane fan-out section of {AddEvmChainConfig} (`remote` is the 32-byte counterpart adapter;
    ///         `gasLimit` 0 = the adapter's default `handle` gas).
    struct HyperlaneSection {
        bool enabled;
        uint32 domain;
        bytes32 remote;
        uint256 gasLimit;
    }

    /// @notice Coverage entries recorded for the new chain (parallel arrays; empty = no coverage recorded).
    struct CoverageSection {
        address[] gateways;
        bool[] hubRouted;
    }

    /// @notice The one-action add-chain config: the EVM `chainId` plus one OPTIONAL section per gateway
    ///         adapter, each guarded by an `enabled` flag so any subset fans out. A section for an adapter
    ///         facet the diamond does not host MUST be left disabled by the admin (the fan-out writes that
    ///         adapter's ERC-7201 slots regardless — they would simply go unread until such a facet is cut).
    struct AddEvmChainConfig {
        uint256 chainId;
        CcipSection ccip;
        LayerZeroSection layerZero;
        WormholeSection wormhole;
        AxelarSection axelar;
        ZetaSection zeta;
        OpL2ToL2Section opL2ToL2;
        CctpSection cctp;
        HyperlaneSection hyperlane;
        CoverageSection coverage;
    }

    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a chain identity is registered.
    event ChainRegistered(bytes32 indexed chainKey, bytes2 chainType, bytes chainReference, uint256 evmChainId);

    /// @notice Emitted when a chain's informational native ids are set.
    event SetNativeIds(bytes32 indexed chainKey, NativeIds ids);

    /// @notice Emitted when a gateway's coverage of a chain is set or cleared.
    event SetGatewayCoverage(bytes32 indexed chainKey, address indexed gateway, bool covered, bool hubRouted);

    /// @notice Emitted once per successful {addEvmChain} fan-out (the per-adapter libs emit their own events).
    event ChainAdded(bytes32 indexed chainKey, uint256 indexed chainId);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The chain identity is already registered (chain identities are permanent — no removal in v1).
    error ChainRegistryAlreadyRegistered(bytes32 chainKey);

    /// @notice The chain identity is not registered yet (register it before configuring it).
    error ChainRegistryNotRegistered(bytes32 chainKey);

    /// @notice The chain reference was empty (an ERC-7930 chain identity needs a reference).
    error ChainRegistryEmptyChainReference();

    /// @notice The coverage gateway was the zero address.
    error ChainRegistryZeroGateway();

    /// @notice The coverage section's `gateways` and `hubRouted` arrays differ in length.
    error ChainRegistryCoverageLengthMismatch(uint256 gateways, uint256 hubRouted);

    /// @notice The Axelar section's `chain7930` is not the canonical chain-only ERC-7930 address of `chainId`.
    error ChainRegistryAxelarChainMismatch();

    /// @notice The Axelar section's `remote7930` does not address the `chainId` being added.
    error ChainRegistryAxelarRemoteMismatch();

    /// @notice An eip-155 registration whose `chainReference` is not the canonical minimal-big-endian encoding
    ///         of `evmChainId` (or whose `evmChainId` is 0) — such a key could never match send-time derivation.
    error ChainRegistryNonCanonicalEvmReference(bytes chainReference, uint256 evmChainId);

    /// @notice A non-EVM registration supplied a non-zero `evmChainId` (meaningless for non-EVM chainTypes).
    error ChainRegistryEvmChainIdOnNonEvmChain(uint256 evmChainId);

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice The chain key of an EVM chain: eip-155 chainType (0x0000) + the canonical minimal big-endian
    ///         chain reference (exactly the `InteroperableAddress.formatEvmV1` encoding — no leading zeros).
    function chainKeyEvm(uint256 chainId) external pure returns (bytes32);

    /// @notice The chain key of any ERC-7930 chain identity:
    ///         `keccak256(abi.encodePacked(chainType, chainReference))`.
    function chainKeyOf(bytes2 chainType, bytes calldata chainReference) external pure returns (bytes32);

    /// @notice Whether `chainKey` is a registered chain identity.
    function isRegistered(bytes32 chainKey) external view returns (bool);

    /// @notice The registered ERC-7930 identity of `chainKey` (`evmChainId` is 0 for non-EVM chains).
    function chainInfoOf(bytes32 chainKey)
        external
        view
        returns (bytes2 chainType, bytes memory chainReference, uint256 evmChainId);

    /// @notice The informational native bridge-ecosystem ids of `chainKey`.
    function nativeIdsOf(bytes32 chainKey) external view returns (NativeIds memory);

    /// @notice The gateway adapters recorded as covering `chainKey` (direct AND hub-routed).
    function gatewaysOf(bytes32 chainKey) external view returns (address[] memory);

    /// @notice The total number of gateways covering `chainKey` (direct + hub-routed).
    function coverageOf(bytes32 chainKey) external view returns (uint256);

    /// @notice The number of gateways covering `chainKey` DIRECTLY (hub-routed coverage never counts).
    /// @dev O(n) over the coverage set — admin-bounded small (one entry per local gateway adapter).
    function directCoverageOf(bytes32 chainKey) external view returns (uint256);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers a chain identity (EVM or non-EVM). Admin only. Reverts
    ///         {ChainRegistryAlreadyRegistered} on re-register — chain identities are permanent in v1.
    /// @param chainType      The ERC-7930 chain type (0x0000 = eip-155).
    /// @param chainReference The ERC-7930 chain reference (for EVM chains use the canonical minimal
    ///                       big-endian chainId encoding, or use {addEvmChain} which builds it).
    /// @param evmChainId     The EVM chainId (informational; 0 for non-EVM chains).
    function registerChain(bytes2 chainType, bytes calldata chainReference, uint256 evmChainId) external;

    /// @notice Sets the informational native ids of a registered chain. Admin only.
    function setNativeIds(bytes32 chainKey, NativeIds calldata ids) external;

    /// @notice Records (or clears) `gateway`'s coverage of a registered chain. Admin only.
    /// @param chainKey  The registered chain key.
    /// @param gateway   The local gateway adapter (non-zero).
    /// @param covered   True to record coverage, false to remove it.
    /// @param hubRouted True when the gateway reaches the chain only via an intermediate hub (e.g. the
    ///                  ZetaChain ZEVM hub) — hub-routed coverage never counts toward {directCoverageOf}.
    function setGatewayCoverage(bytes32 chainKey, address gateway, bool covered, bool hubRouted) external;

    /// @notice ONE structured admin action that adds an EVM chain everywhere: registers the chain identity
    ///         (eip-155 + canonical minimal big-endian reference), records the native ids declared by the
    ///         enabled sections, then fans the per-adapter config out into every ENABLED gateway adapter's own
    ///         ERC-7201 storage via direct internal lib calls (msg.sender stays the admin — never external
    ///         self-calls), and finally records the coverage entries. Admin only.
    /// @dev Reverts {ChainRegistryAlreadyRegistered} if the chain identity already exists. Sections for
    ///      adapter facets the diamond does not host must be left disabled (see {AddEvmChainConfig}).
    function addEvmChain(AddEvmChainConfig calldata cfg) external;
}
