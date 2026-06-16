// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IUpgradeRegistry} from "@lattice/interfaces/IUpgradeRegistry.sol";
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

    /// @dev Forces solc to emit the struct type into `storageLayout`. Never read, never deployed.
    GovernedDiamondCutStorage internal _unusedGovernedDiamondCut;
}
