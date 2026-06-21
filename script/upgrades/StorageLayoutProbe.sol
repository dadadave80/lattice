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
}
