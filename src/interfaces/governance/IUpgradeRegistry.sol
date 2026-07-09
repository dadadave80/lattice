// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IUpgradeRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Read interface for the append-only, versioned upgrade registry maintained by the
///         {GovernedDiamondCut} facet. Every successfully-authorized-and-applied governed cut is
///         recorded under a monotonically increasing `version` (== the cut counter value assigned to
///         that cut), giving anyone an on-chain audit trail of the Diamond's upgrade history.
/// @dev This interface is intentionally SEPARATE from {IGovernedDiamondCut}: that interface exposes
///      only `diamondCut`, so `type(IGovernedDiamondCut).interfaceId == 0x1f931c1c` (identical to
///      `IDiamondCut`), which is load-bearing — the governed facet must occupy the canonical cut
///      selector. The registry getters/struct/event therefore live here so they cannot perturb that
///      pinned id. The registry is NOT advertised as a distinct ERC-165 interface: its getters are
///      plain facet views, so no new ERC-165 map slot is registered for it.
interface IUpgradeRegistry {
    /// @notice An immutable audit record of a single governed cut.
    /// @dev Packs into two storage words: (cutHash) + (executor | executedAt | facetCutCount) and
    ///      (init). Append-only — fields are only ever added at the end, never reordered or retyped.
    /// @param cutHash `keccak256(abi.encode(_diamondCut, _init, _calldata))` of the applied cut — a
    ///        tamper-evident fingerprint of exactly what was executed.
    /// @param executor The caller that passed the role gate (the timelock relaying a passed proposal).
    /// @param executedAt The `block.timestamp` (as uint48) at which the cut was applied.
    /// @param facetCutCount The number of FacetCut entries in the applied cut.
    /// @param init The init address delegatecalled after the cut (address(0) if none).
    struct CutRecord {
        bytes32 cutHash;
        address executor;
        uint48 executedAt;
        uint32 facetCutCount;
        address init;
    }

    /// @dev Emitted after a governed cut is recorded in the registry under `version`. Complements
    ///      {IGovernedDiamondCut-UpgradeExecuted}: that signals the guard passed; this anchors the
    ///      immutable audit entry and its `version`.
    /// @param version The monotonic registry version assigned to this cut (1-indexed).
    /// @param cutHash `keccak256(abi.encode(_diamondCut, _init, _calldata))` of the applied cut.
    /// @param executor The caller that passed the role gate (the timelock relaying a passed proposal).
    event CutRecorded(uint256 indexed version, bytes32 cutHash, address indexed executor);

    /// @notice Returns the number of governed cuts recorded so far, which is also the latest version.
    function cutCount() external view returns (uint256);

    /// @notice Returns the immutable audit record for a given registry `version`.
    /// @dev Versions are 1-indexed; an unwritten version (0, or any value > {cutCount}) returns a
    ///      zero-valued {CutRecord}.
    /// @param version The registry version to look up.
    function getCutRecord(uint256 version) external view returns (CutRecord memory);
}
