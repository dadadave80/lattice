// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";

/// @title IFrozenSelectors
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Protection layer for the {GovernedDiamondCut} facet: a governance-curated, append-only set
///         of "frozen" function selectors that can never be `Replace`d or `Remove`d by a subsequent
///         governed cut, plus a pre-flight simulator and an ERC-165 verification helper for upgrade
///         workflows. Freezing the loupe selectors or the cut selector itself makes a diamond unable
///         to brick its own introspection/upgrade path through a (mistaken or malicious) cut.
/// @dev This interface is intentionally SEPARATE from {IGovernedDiamondCut}: that interface exposes
///      only `diamondCut`, so `type(IGovernedDiamondCut).interfaceId == 0x1f931c1c` (identical to
///      `IDiamondCut`), which is load-bearing — the governed facet must occupy the canonical cut
///      selector. The freeze/preview/verify surface therefore lives here so it cannot perturb that
///      pinned id. None of these functions are advertised as a distinct ERC-165 interface: they are
///      plain facet admin/view functions, so no new ERC-165 map slot is registered for them.
interface IFrozenSelectors {
    /// @dev Emitted once per `freezeSelectors` call that adds at least one new selector. Carries the
    ///      full argument array as passed (including any selectors that were already frozen, which are
    ///      idempotent no-ops in the set).
    /// @param caller The UPGRADE_EXECUTOR_ROLE holder that froze the selectors (the timelock relay).
    /// @param selectors The selectors supplied to `freezeSelectors`.
    event SelectorsFrozen(address indexed caller, bytes4[] selectors);

    /// @dev Thrown by the guarded `diamondCut` (and surfaced via `previewCut`) when a `Replace` or
    ///      `Remove` cut targets a frozen selector. `Add` actions are never affected.
    /// @param selector The frozen selector a cut attempted to replace or remove.
    error FrozenSelectorProtected(bytes4 selector);

    /// @notice Permanently marks `selectors` as frozen: once frozen, a selector can never be the
    ///         target of a `Replace` or `Remove` in any future governed cut. Append-only — there is
    ///         deliberately no unfreeze. Gated behind UPGRADE_EXECUTOR_ROLE (the same single-holder
    ///         role that gates `diamondCut`), so only a timelock-relayed governance proposal can freeze.
    /// @param selectors The function selectors to freeze. Already-frozen selectors are idempotent.
    function freezeSelectors(bytes4[] calldata selectors) external;

    /// @notice Returns whether `selector` is in the frozen set.
    /// @param selector The function selector to query.
    /// @return frozen `true` if the selector is frozen (protected from Replace/Remove).
    function isSelectorFrozen(bytes4 selector) external view returns (bool frozen);

    /// @notice Returns the full set of frozen selectors.
    /// @return selectors The frozen selectors, in insertion order (subject to swap-and-pop reordering
    ///         on internal set mechanics, though the set is append-only so order is stable here).
    function frozenSelectors() external view returns (bytes4[] memory selectors);

    /// @notice Pre-flight simulation of the frozen-selector guard against the CURRENT frozen set, with
    ///         no state change and no broadcast. Lets an upgrade workflow fail fast — before proposing
    ///         — if a cut would touch a frozen selector. Mirrors exactly the check the guarded
    ///         `diamondCut` performs before applying: only `Replace`/`Remove` actions are inspected.
    /// @dev This is a pure read of the frozen set; it does NOT re-implement diamond-lib's collision /
    ///      immutable-function / bytecode-existence checks, which fire at execution time.
    /// @param cuts The candidate facet cuts to simulate.
    /// @return ok `true` if no `Replace`/`Remove` in `cuts` targets a frozen selector.
    /// @return offendingSelector The first frozen selector a `Replace`/`Remove` would touch (zero if `ok`).
    function previewCut(FacetCut[] calldata cuts) external view returns (bool ok, bytes4 offendingSelector);

    /// @notice Verifies whether `interfaceId` is currently advertised in the diamond's ERC-165 map.
    /// @dev A thin wrapper over the shared ERC-165 support read, so an upgrade workflow can confirm an
    ///      expected interface is still (or now) advertised after a cut. Equivalent to calling
    ///      `supportsInterface(interfaceId)` on the diamond.
    /// @param interfaceId The ERC-165 interface identifier to check.
    /// @return registered `true` if the interface is advertised.
    function verifyInterfaceRegistered(bytes4 interfaceId) external view returns (bool registered);
}
