// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";

/// @title IEmergencyCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Emergency escape-hatch surface for the {GovernedDiamondCut} facet: a zero-delay,
///         REMOVAL-ONLY diamond cut a guardian can fire to instantly unbind a compromised or buggy
///         facet — even while the normal governed cut path is halted by EmergencyStop. It is
///         deliberately constrained: a guardian may only `Remove` selectors (never `Add`/`Replace`,
///         which still require a full governance round) and may never remove a frozen, load-bearing
///         selector (the loupe or the cut path itself).
/// @dev This interface is intentionally SEPARATE from {IGovernedDiamondCut}: that interface exposes
///      only `diamondCut`, so `type(IGovernedDiamondCut).interfaceId == 0x1f931c1c` (identical to
///      `IDiamondCut`), which is load-bearing — the governed facet must occupy the canonical cut
///      selector. The emergency-removal surface therefore lives here so it cannot perturb that pinned
///      id. `emergencyRemoveCut` is a plain facet admin function and is NOT advertised as a distinct
///      ERC-165 interface, so no new ERC-165 map slot is registered for it. Emergency removals are
///      recorded in the same append-only {IUpgradeRegistry} as governed cuts, so they appear in cut
///      history, and additionally emit {EmergencyCutExecuted} so they are auditable as panic actions.
interface IEmergencyCut {
    /// @dev Emitted after a guardian successfully applies an emergency removal-only cut. Complements
    ///      {IUpgradeRegistry-CutRecorded} (which anchors the immutable registry entry): this flags
    ///      that the cut traveled the EMERGENCY path (guardian-gated, EmergencyStop-bypassing,
    ///      removal-only) rather than the full governance path.
    /// @param version The monotonic registry version assigned to this emergency cut (1-indexed),
    ///        shared with the governed-cut registry so emergency removals appear in cut history.
    /// @param guardian The EMERGENCY_GUARDIAN_ROLE holder that fired the emergency removal.
    /// @param selectorCount The total number of function selectors removed across all FacetCut entries.
    event EmergencyCutExecuted(uint256 indexed version, address indexed guardian, uint256 selectorCount);

    /// @dev Thrown when an emergency cut contains a FacetCut whose action is not `Remove`. The
    ///      emergency path is removal-only; any `Add` (0) or `Replace` (1) is rejected with the
    ///      offending action so a rogue or mistaken guardian can never add or replace code.
    /// @param action The offending {FacetCutAction} (0 == Add, 1 == Replace) that was not Remove (2).
    error EmergencyCutMustBeRemoveOnly(uint8 action);

    /// @notice Zero-delay, removal-only emergency cut: instantly unbinds the supplied selectors from
    ///         the diamond. Callable ONLY by an EMERGENCY_GUARDIAN_ROLE holder, and — unlike the
    ///         governed `diamondCut` — it INTENTIONALLY works while EmergencyStop is engaged (it is the
    ///         panic button). Every FacetCut must use action `Remove` (revert
    ///         {EmergencyCutMustBeRemoveOnly} otherwise); none may target a frozen selector (revert
    ///         {IFrozenSelectors-FrozenSelectorProtected}); no init delegatecall is permitted (nothing
    ///         to initialize on a pure removal). The removal is recorded in the {IUpgradeRegistry} and
    ///         emits {EmergencyCutExecuted}.
    /// @param cuts The facet cuts to apply; every entry MUST be a `Remove` (facetAddress == address(0)).
    function emergencyRemoveCut(FacetCut[] calldata cuts) external;
}
