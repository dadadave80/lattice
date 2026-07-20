// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";

/// @title ILatticeRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Read / admin surface of the {LatticeRegistry} singleton — the two-tier, immutable, deploy-once
///         address book that lets every Lattice diamond reuse canonical facet bytecode instead of
///         re-`CREATE`ing byte-identical facets on every deployment.
/// @dev TRUST MODEL (issue #118). The registry is deliberately a standalone, NON-upgradeable plain contract
///      (no diamond, no ERC-7201, no proxy) — the smallest possible trust surface for the thing every
///      deployment depends on. Two tiers:
///
///      - Tier A (permissionless, trustless): {attest} / {resolve}. A content-addressed codehash → address
///        map. `attest` is self-verifying (it reads `deployed.codehash` on-chain — impossible to spoof) and
///        first-write-wins; any address with a given runtime codehash is `delegatecall`-equivalent, so one
///        entry serves all. No curation, no admin.
///      - Tier B (curated, append-only): {register} / {setLatest} + views. `Ownable2Step` (→ multisig)
///        governs ONLY this namespace. A `(nameHash, version)` record is IMMUTABLE once written (invariant
///        I1) — never repointed; `latest(nameHash)` is a curator-movable convenience pointer that
///        security-critical consumers ignore in favour of pinning an exact version (invariant I3). Curated
///        facets MUST implement ERC-8153 `exportSelectors()`; {register} pulls and validates the selectors
///        and pins `keccak256(rawBlob)`, and the live-read views re-verify against that pin so an impure or
///        lying `exportSelectors()` can never drift the cut a consumer receives (invariant I2 for selectors).
///
///      `version` is a semver value packed into a `uint64` as `major (16 bits) | minor (24) | patch (24)`
///      (`(major << 48) | (minor << 24) | patch`), so lexicographic `uint64` ordering equals semver
///      ordering. The registry treats it as an OPAQUE, ordered key; it never decodes the fields. Packed
///      version `0` (i.e. 0.0.0) is RESERVED as the "latest unset" sentinel and is not registrable.
interface ILatticeRegistry {
    //*//////////////////////////////////////////////////////////////////////////
    //                                   TYPES
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A curated Tier-B facet record, immutable once written (invariant I1).
    /// @param facet The canonical facet address whose selectors are pinned by this record.
    /// @param version Semver packed `uint64` (`major<<48 | minor<<24 | patch`); opaque ordered key.
    /// @param registeredAt Block timestamp of registration (`uint48` — good past the year 8·10^6).
    /// @param codehash `facet.codehash` captured at registration (also mirrored into Tier A).
    /// @param selectorsHash `keccak256` of the tightly packed selector blob returned by
    ///        `IERC8153(facet).exportSelectors()` at registration — the drift pin the live-read views check.
    struct Record {
        address facet;
        uint64 version;
        uint48 registeredAt;
        bytes32 codehash;
        bytes32 selectorsHash;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Emitted the first time a runtime `codehash` is attested into the Tier-A resolver.
    /// @param codehash The runtime codehash that now resolves to `deployed`.
    /// @param deployed The first address seen carrying `codehash` (first-write-wins).
    event Attested(bytes32 indexed codehash, address indexed deployed);

    /// @notice Emitted when a new curated `(nameHash, version)` record is written.
    /// @param nameHash The curated name key.
    /// @param version The semver-packed version key.
    /// @param facet The canonical facet address.
    /// @param codehash The facet's runtime codehash (also auto-attested into Tier A).
    /// @param selectorsHash The pinned `keccak256` of the facet's exported selector blob.
    event Registered(
        bytes32 indexed nameHash, uint64 indexed version, address indexed facet, bytes32 codehash, bytes32 selectorsHash
    );

    /// @notice Emitted when the `latest` convenience pointer for a name is set or moved (rollbacks allowed).
    /// @param nameHash The curated name key.
    /// @param version The version now flagged as `latest` for `nameHash`.
    event LatestSet(bytes32 indexed nameHash, uint64 indexed version);

    /// @notice Emitted when a two-step ownership handover is initiated by the current owner.
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when ownership is transferred (construction, and on `acceptOwnership`).
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Thrown when a constructor / handover would set a zero owner.
    error LatticeRegistry__ZeroAddress();

    /// @notice Thrown when a non-owner calls an `onlyOwner` function.
    error LatticeRegistry__Unauthorized(address caller);

    /// @notice Thrown when an account other than the pending owner calls {acceptOwnership}.
    error LatticeRegistry__NotPendingOwner(address caller);

    /// @notice Thrown when {attest} / {register} targets an address with no runtime code (EOA / empty — I4).
    error LatticeRegistry__EmptyCode(address target);

    /// @notice Thrown when {register} uses the reserved sentinel version `0` (0.0.0).
    error LatticeRegistry__InvalidVersion();

    /// @notice Thrown when {register} would overwrite an existing `(nameHash, version)` record (I1).
    error LatticeRegistry__RecordExists(bytes32 nameHash, uint64 version);

    /// @notice Thrown when a view / {setLatest} references a `(nameHash, version)` that was never registered.
    error LatticeRegistry__RecordNotFound(bytes32 nameHash, uint64 version);

    /// @notice Thrown when {latest} is read for a name whose pointer was never set.
    error LatticeRegistry__LatestUnset(bytes32 nameHash);

    /// @notice Thrown when a curated facet does not satisfy the ERC-8153 selector contract at {register}
    ///         (call reverts / returns nothing / empty selectors / length not a multiple of 4 / duplicates /
    ///         a blob that self-includes `exportSelectors()` (`0x0ef22643`), which must never be cut).
    error LatticeRegistry__NotERC8153(address facet);

    /// @notice Thrown by the live-read views when `keccak256(exportSelectors())` no longer equals the pinned
    ///         `selectorsHash` — an impure or mutated facet (invariant I2 for selectors).
    error LatticeRegistry__SelectorDrift(address facet);

    /// @notice Thrown by the live-read views when the facet's current `codehash` no longer equals the codehash
    ///         pinned at registration — defends against a metamorphic (CREATE2 + `selfdestruct` + redeploy)
    ///         address swap that keeps `exportSelectors()` byte-identical (invariant I2 for code).
    error LatticeRegistry__CodeDrift(address facet);

    //*//////////////////////////////////////////////////////////////////////////
    //                          TIER A — CODEHASH RESOLVER
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Permissionlessly record that `deployed` carries a given runtime codehash (first-write-wins).
    /// @dev Self-verifying: reads `deployed.codehash` on-chain; reverts {LatticeRegistry__EmptyCode} for an
    ///      EOA / empty account. Re-attesting an already-mapped codehash is a documented silent no-op — the
    ///      mapping is immutable once set, so the first attester wins and no event re-fires.
    /// @param deployed The address whose runtime code should be indexed.
    function attest(address deployed) external;

    /// @notice Resolve a runtime `codehash` to the first address attested with it (0 if none).
    /// @param codehash The runtime codehash to look up.
    /// @return deployed The first attested address, or `address(0)` if unmapped.
    function resolve(bytes32 codehash) external view returns (address deployed);

    //*//////////////////////////////////////////////////////////////////////////
    //                          TIER B — CURATED CATALOG
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Register a new curated facet under `(nameHash, version)` (owner-only, append-only).
    /// @dev Reverts {LatticeRegistry__RecordExists} if the record already exists (I1),
    ///      {LatticeRegistry__InvalidVersion} for version `0`, {LatticeRegistry__EmptyCode} for a codeless
    ///      facet, and {LatticeRegistry__NotERC8153} if `IERC8153(facet).exportSelectors()` fails the ERC-8153
    ///      contract. Pins `keccak256(selectors)`, mirrors the codehash into Tier A, and emits {Registered}.
    /// @param nameHash The curated name key.
    /// @param version The semver-packed version (must be non-zero).
    /// @param facet The canonical facet address (must have code and implement ERC-8153).
    function register(bytes32 nameHash, uint64 version, address facet) external;

    /// @notice Point `latest(nameHash)` at an already-registered `version` (owner-only).
    /// @dev The target record must exist ({LatticeRegistry__RecordNotFound} otherwise). Moving the pointer to
    ///      an OLDER version is allowed — it is only a convenience pointer, never the pinned record (I3).
    /// @param nameHash The curated name key.
    /// @param version The registered version to flag as latest.
    function setLatest(bytes32 nameHash, uint64 version) external;

    /// @notice Read the exact record for `(nameHash, version)`.
    /// @dev Reverts {LatticeRegistry__RecordNotFound} if unregistered.
    function get(bytes32 nameHash, uint64 version) external view returns (Record memory record);

    /// @notice Read the record currently flagged as `latest` for a name.
    /// @dev Reverts {LatticeRegistry__LatestUnset} if {setLatest} was never called for `nameHash`.
    function latest(bytes32 nameHash) external view returns (Record memory record);

    /// @notice Live-read and drift-verify the facet's selectors for `(nameHash, version)`.
    /// @dev Reverts {LatticeRegistry__RecordNotFound} if unregistered, {LatticeRegistry__CodeDrift} if
    ///      `facet.codehash` no longer equals the pinned codehash, and {LatticeRegistry__SelectorDrift} if
    ///      `keccak256(exportSelectors())` no longer equals the pinned `selectorsHash`. A facet that reverts,
    ///      self-destructs, or returns a malformed blob is caught by the code/selector pins (an unmatchable or
    ///      undecodable live read never satisfies both pins), so the call always reverts rather than returning a
    ///      stale cut. Then unpacks the blob to `bytes4[]`.
    function getSelectors(bytes32 nameHash, uint64 version) external view returns (bytes4[] memory selectors);

    /// @notice Live-read, drift-verify, and assemble a ready-to-apply `Add` {FacetCut} for `(nameHash, version)`.
    /// @dev Same code + selector drift verification as {getSelectors}; the returned cut uses `FacetCutAction.Add`.
    function getCut(bytes32 nameHash, uint64 version) external view returns (FacetCut memory cut);

    //*//////////////////////////////////////////////////////////////////////////
    //                   TIER B — STRING-NAME CONVENIENCE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Compute the registry key for a canonical facet name: `keccak256(bytes(name))`.
    /// @dev For callers interacting DIRECTLY with the contract (Etherscan, etc.) so they need not pre-hash a name
    ///      off-chain. The registry hashes the RAW string and applies NO prefix, so the string overloads below
    ///      and the `bytes32` overloads are interchangeable when passed the same full canonical name. By
    ///      CONVENTION Lattice facets are registered under `"lattice.<FacetName>"` (e.g. `"lattice.ERC20"`).
    /// @param name The full canonical facet name.
    /// @return The `bytes32` nameHash used by every Tier-B function.
    function nameHash(string calldata name) external pure returns (bytes32);

    /// @notice {register} by canonical name string instead of its precomputed hash (owner-only).
    function register(string calldata name, uint64 version, address facet) external;

    /// @notice {setLatest} by canonical name string (owner-only).
    function setLatest(string calldata name, uint64 version) external;

    /// @notice {get} the exact record for a canonical name string.
    function get(string calldata name, uint64 version) external view returns (Record memory record);

    /// @notice {latest} record for a canonical name string.
    function latest(string calldata name) external view returns (Record memory record);

    /// @notice {getSelectors} for a canonical name string.
    function getSelectors(string calldata name, uint64 version) external view returns (bytes4[] memory selectors);

    /// @notice {getCut} for a canonical name string.
    function getCut(string calldata name, uint64 version) external view returns (FacetCut memory cut);

    //*//////////////////////////////////////////////////////////////////////////
    //                          OWNERSHIP (Ownable2Step)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The current owner of the curated Tier-B namespace.
    function owner() external view returns (address);

    /// @notice The address that may call {acceptOwnership} to complete a pending handover (0 if none).
    function pendingOwner() external view returns (address);

    /// @notice Begin a two-step ownership handover to `newOwner` (owner-only; pass `address(0)` to cancel).
    function transferOwnership(address newOwner) external;

    /// @notice Complete a pending ownership handover (pending-owner-only).
    function acceptOwnership() external;
}
