// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICommitReveal} from "@lattice/interfaces/ICommitReveal.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/IUpgradeRegistry.sol";
import {IncrementalMerkleTreeLib} from "@lattice/privacy/libraries/IncrementalMerkleTreeLib.sol";
import {NullifierRegistryLib} from "@lattice/privacy/libraries/NullifierRegistryLib.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";

/// @title StorageLayoutProbe
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Compile-only harness that re-declares a module's ERC-7201 storage struct as a CONTRACT
///         STATE VARIABLE so Foundry's `forge inspect <Probe> storageLayout` surfaces the struct's
///         field-by-field layout (slot / offset / type) for the append-only-struct safety check.
/// @dev WHY THIS EXISTS: a Lattice module's storage struct lives inside its `*Lib.sol` library and is
///      only ever reached through an `assembly { $.slot := <CONST> }` cast. Because the struct is never
///      a real state variable of any contract, the solc-emitted `storageLayout` of the library (and of
///      the stateless facet) is EMPTY — there is nothing for the append-only check to diff. Mirroring
///      the struct here, as `internal` state, is the standard Foundry idiom for making an ERC-7201
///      namespaced layout inspectable. This is purely a build/CI artifact: it is NEVER deployed, holds
///      no real storage, and the `_unused*` variables are only there to force solc to materialize the
///      struct type into the artifact's `storageLayout.types`.
///
///      INVARIANT BEING ENFORCED (see CLAUDE.md "Append-only storage struct rule"): an ERC-7201 struct
///      may only be EXTENDED by appending fields — never reorder, retype, shrink, or remove an existing
///      field. `script/upgrades/check-storage-layout.sh` diffs the inspected layout of THIS struct
///      against the committed baseline and fails CI on any incompatible change.
///
///      KEEP IN SYNC: when you add an append-only field to a real module struct (e.g.
///      `GovernedDiamondCutStorage` in `GovernedDiamondCutLib.sol`), append the SAME field here, then
///      regenerate the baseline (`check-storage-layout.sh --update`). The structs below must be a
///      verbatim copy of the live ones; the check script's whole point is to catch the case where they
///      diverge incompatibly. Add a new probe field per module you want guarded.
contract StorageLayoutProbe {
    /// @dev Verbatim mirror of `GovernedDiamondCutLib.GovernedDiamondCutStorage`
    ///      (`@custom:storage-location erc7201:lattice.storage.GovernedDiamondCut`). Append-only.
    struct GovernedDiamondCutStorage {
        uint256 _cutCount;
        mapping(uint256 version => IUpgradeRegistry.CutRecord record) _cutRegistry;
        EnumerableSet.Bytes4Set _frozenSelectors;
    }

    /// @dev Verbatim mirror of `SafeDiamondCutLib.SafeDiamondCutStorage`
    ///      (`@custom:storage-location erc7201:lattice.storage.SafeDiamondCut`). Append-only.
    struct SafeDiamondCutStorage {
        address _safe;
        uint256 _cutCount;
        mapping(uint256 version => IUpgradeRegistry.CutRecord record) _cutRegistry;
        EnumerableSet.Bytes4Set _frozenSelectors;
    }

    /// @dev Verbatim mirror of `GovernedSafeDiamondCutLib.GovernedSafeDiamondCutStorage`
    ///      (`@custom:storage-location erc7201:lattice.storage.GovernedSafeDiamondCut`). Append-only.
    struct GovernedSafeDiamondCutStorage {
        address _safe;
        uint256 _minDelay;
        mapping(bytes32 id => uint256 eta) _scheduledAt;
        uint256 _cutCount;
        mapping(uint256 version => IUpgradeRegistry.CutRecord record) _cutRegistry;
        EnumerableSet.Bytes4Set _frozenSelectors;
    }

    /// @dev Verbatim mirror of `ERC6538RegistryLib.ERC6538RegistryStorage`
    ///      (`@custom:storage-location erc7201:lattice.storage.ERC6538Registry`). Append-only.
    struct ERC6538RegistryStorage {
        mapping(address registrant => mapping(uint256 schemeId => bytes stealthMetaAddress)) _stealthMetaAddresses;
        mapping(address registrant => uint256 nonce) _nonces;
    }

    /// @dev Verbatim mirror of `ENSReverseClaimerLib.ENSReverseClaimerStorage`
    ///      (`@custom:storage-location erc7201:lattice.storage.ENSReverseClaimer`). Append-only.
    struct ENSReverseClaimerStorage {
        address _reverseRegistrar;
        string _ensName;
    }

    /// @dev Verbatim mirror of `ENSResolverLib.ENSResolverStorage`
    ///      (`@custom:storage-location erc7201:lattice.storage.ENSResolver`). Append-only.
    struct ENSResolverStorage {
        address _ensRegistry;
    }

    /// @dev Verbatim mirror of `ENSSubnameIssuerLib.ENSSubnameIssuerStorage`
    ///      (`@custom:storage-location erc7201:lattice.storage.ENSSubnameIssuer`). Append-only.
    struct ENSSubnameIssuerStorage {
        address _nameWrapper;
    }

    /// @dev Verbatim mirror of `SafeHarborAdopterLib.SafeHarborAdopterStorage`
    ///      (`@custom:storage-location erc7201:lattice.storage.SafeHarborAdopter`). Append-only.
    struct SafeHarborAdopterStorage {
        address _safeHarborRegistry;
        address _agreementFactory;
    }

    /// @dev Verbatim mirror of `CommitRevealLib.CommitRevealStorage`
    ///      (`@custom:storage-location erc7201:lattice.storage.CommitReveal`). Append-only.
    struct CommitRevealStorage {
        mapping(bytes32 commitment => ICommitReveal.Commitment record) _commitments;
    }

    /// @dev Verbatim mirror of `SemaphoreLib.SemaphoreStorage` and its `Group`
    ///      (`@custom:storage-location erc7201:lattice.storage.Semaphore`). Append-only.
    struct Group {
        IncrementalMerkleTreeLib.Tree tree;
        NullifierRegistryLib.Registry nullifiers;
        address admin;
        bool exists;
    }

    struct SemaphoreStorage {
        mapping(uint256 groupId => Group group) groups;
        uint256 groupCount;
        address verifier;
    }

    /// @dev Verbatim mirror of `PrivateVotingLib.PrivateVotingStorage` and its `Poll`
    ///      (`@custom:storage-location erc7201:lattice.storage.PrivateVoting`). Append-only.
    struct Poll {
        uint256 groupId;
        NullifierRegistryLib.Registry nullifiers;
        mapping(uint256 choice => uint256 votes) tally;
        uint256 totalVotes;
        address creator;
        uint32 numChoices;
        uint64 startTime;
        uint64 endTime;
        bool exists;
    }

    struct PrivateVotingStorage {
        mapping(uint256 pollId => Poll poll) _polls;
        uint256 _pollCount;
    }

    /// @dev Verbatim mirror of `ShieldedPoolLib.ShieldedPoolStorage` and its `ShieldedPool`
    ///      (`@custom:storage-location erc7201:lattice.storage.ShieldedPool`). Append-only.
    struct ShieldedPool {
        IncrementalMerkleTreeLib.Tree commitments;
        NullifierRegistryLib.Registry nullifiers;
        address token;
        uint256 denomination;
        address verifier;
        bool exists;
    }

    struct ShieldedPoolStorage {
        mapping(uint256 poolId => ShieldedPool pool) _pools;
        uint256 _poolCount;
    }

    /// @dev Verbatim mirror of `PythAdapterLib.PythAdapterStorage` and its `PythFeed`
    ///      (`@custom:storage-location erc7201:lattice.storage.PythAdapter`). Append-only.
    struct PythFeed {
        bytes32 priceId;
        uint48 maxStaleness;
        uint64 maxConfBps;
    }

    struct PythAdapterStorage {
        mapping(bytes32 key => PythFeed) _feeds;
        address _pyth;
    }

    /// @dev Verbatim mirror of `API3AdapterLib.API3AdapterStorage` and its `API3Feed`
    ///      (`@custom:storage-location erc7201:lattice.storage.API3Adapter`). Append-only.
    struct API3Feed {
        address proxy;
        uint48 maxStaleness;
    }

    struct API3AdapterStorage {
        mapping(bytes32 key => API3Feed) _feeds;
    }

    /// @dev Verbatim mirror of `ChronicleAdapterLib.ChronicleAdapterStorage` and its `ChronicleFeed`
    ///      (`@custom:storage-location erc7201:lattice.storage.ChronicleAdapter`). Append-only.
    struct ChronicleFeed {
        address chronicle;
        uint48 maxStaleness;
    }

    struct ChronicleAdapterStorage {
        mapping(bytes32 key => ChronicleFeed) _feeds;
    }

    /// @dev Verbatim mirror of `DIAAdapterLib.DIAAdapterStorage` and its `DIAFeed`
    ///      (`@custom:storage-location erc7201:lattice.storage.DIAAdapter`). Append-only.
    struct DIAFeed {
        address oracle;
        uint48 maxStaleness;
        string diaKey;
    }

    struct DIAAdapterStorage {
        mapping(bytes32 key => DIAFeed) _feeds;
    }

    /// @dev Verbatim mirror of `BandAdapterLib.BandAdapterStorage` and its `BandFeed`
    ///      (`@custom:storage-location erc7201:lattice.storage.BandAdapter`). Append-only.
    struct BandFeed {
        uint48 maxStaleness;
        string base;
        string quote;
    }

    struct BandAdapterStorage {
        mapping(bytes32 key => BandFeed) _feeds;
        address _reference;
    }

    /// @dev Verbatim mirror of `TellorAdapterLib.TellorAdapterStorage` and its `TellorFeed`
    ///      (`@custom:storage-location erc7201:lattice.storage.TellorAdapter`). Append-only.
    struct TellorFeed {
        bytes32 queryId;
        uint48 disputeBuffer;
        uint48 maxStaleness;
    }

    struct TellorAdapterStorage {
        mapping(bytes32 key => TellorFeed) _feeds;
        address _tellor;
    }

    /// @dev Verbatim mirror of `RedStoneAdapterLib.RedStoneAdapterStorage` and its `RedStoneFeed`
    ///      (`@custom:storage-location erc7201:lattice.storage.RedStoneAdapter`). Append-only.
    struct RedStoneFeed {
        address adapter;
        uint48 maxStaleness;
        bytes32 dataFeedId;
    }

    struct RedStoneAdapterStorage {
        mapping(bytes32 key => RedStoneFeed) _feeds;
    }

    /// @dev Verbatim mirror of `CrosschainLinkLib.CrosschainLinkStorage` and its `Link`
    ///      (`@custom:storage-location erc7201:lattice.storage.CrosschainLink`). Append-only.
    struct Link {
        address gateway;
        bytes counterpart;
    }

    struct CrosschainLinkStorage {
        mapping(bytes chain => Link) _links;
        mapping(bytes4 tag => address handler) _handlers;
        mapping(bytes32 usedKey => bool used) _used;
    }

    /// @dev Verbatim mirror of `BridgeERC20Lib.BridgeERC20Storage`
    ///      (`@custom:storage-location erc7201:lattice.storage.BridgeERC20`). Append-only.
    struct BridgeERC20Storage {
        address _token;
    }

    /// @dev Verbatim mirror of `BridgeERC7802Lib.BridgeERC7802Storage`
    ///      (`@custom:storage-location erc7201:lattice.storage.BridgeERC7802`). Append-only.
    struct BridgeERC7802Storage {
        address _token;
    }

    /// @dev Verbatim mirror of `AxelarGatewayAdapterLib.AxelarGatewayAdapterStorage`
    ///      (`@custom:storage-location erc7201:lattice.storage.AxelarGatewayAdapter`). Append-only.
    struct AxelarGatewayAdapterStorage {
        address _gateway;
        mapping(bytes2 chainType => mapping(bytes chainReference => bytes addr)) _remoteGateways;
        mapping(bytes chain => string axelar) _erc7930ToAxelar;
        mapping(string axelar => bytes chain) _axelarToErc7930;
    }

    /// @dev Verbatim mirror of `WormholeGatewayAdapterLib.WormholeGatewayAdapterStorage` and its
    ///      `PendingMessage` (`@custom:storage-location erc7201:lattice.storage.WormholeGatewayAdapter`). Append-only.
    struct PendingMessage {
        address sender;
        uint256 value;
        bytes recipient;
        bytes payload;
    }

    struct WormholeGatewayAdapterStorage {
        address _relayer;
        uint16 _wormholeChainId;
        uint256 _lastMsgId;
        mapping(uint256 chainId => address remote) _remoteGateways;
        mapping(uint256 chainId => uint16 wormhole) _chainIdToWormhole;
        mapping(uint16 wormhole => uint256 chainId) _wormholeToChainId;
        mapping(bytes32 sendId => PendingMessage) _pending;
        mapping(uint256 chainId => mapping(uint256 sendId => bool used)) _executed;
    }

    /// @dev Forces solc to emit the struct types into `storageLayout`. Never read, never deployed.
    GovernedDiamondCutStorage internal _unusedGovernedDiamondCut;
    SafeDiamondCutStorage internal _unusedSafeDiamondCut;
    GovernedSafeDiamondCutStorage internal _unusedGovernedSafeDiamondCut;
    ERC6538RegistryStorage internal _unusedERC6538Registry;
    ENSReverseClaimerStorage internal _unusedENSReverseClaimer;
    ENSResolverStorage internal _unusedENSResolver;
    ENSSubnameIssuerStorage internal _unusedENSSubnameIssuer;
    SafeHarborAdopterStorage internal _unusedSafeHarborAdopter;
    CommitRevealStorage internal _unusedCommitReveal;
    SemaphoreStorage internal _unusedSemaphore;
    PrivateVotingStorage internal _unusedPrivateVoting;
    ShieldedPoolStorage internal _unusedShieldedPool;
    PythAdapterStorage internal _unusedPythAdapter;
    API3AdapterStorage internal _unusedAPI3Adapter;
    ChronicleAdapterStorage internal _unusedChronicleAdapter;
    DIAAdapterStorage internal _unusedDIAAdapter;
    BandAdapterStorage internal _unusedBandAdapter;
    TellorAdapterStorage internal _unusedTellorAdapter;
    RedStoneAdapterStorage internal _unusedRedStoneAdapter;
    CrosschainLinkStorage internal _unusedCrosschainLink;
    BridgeERC20Storage internal _unusedBridgeERC20;
    BridgeERC7802Storage internal _unusedBridgeERC7802;
    AxelarGatewayAdapterStorage internal _unusedAxelarGatewayAdapter;
    WormholeGatewayAdapterStorage internal _unusedWormholeGatewayAdapter;
}
