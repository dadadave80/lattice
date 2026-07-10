// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, ERC165_MAP_ILOUPE_SLOT} from "@diamond/libraries/DiamondLib.sol";

/// @title DiamondIntrospectionInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot ERC-165 flag registration for a recipe's introspection/upgrade surface, appended to a
///         recipe's init chain via `MultiInit`. TWO truthful variants — a flag is registered iff the facet
///         is actually cut:
///         - {initUpgradeable}: the recipe cuts BOTH `DiamondLoupeFacet` AND a `diamondCut`-carrying facet
///           — registers `IDiamondLoupe` (0x48e2b093) and `IDiamondCut` (0x1f931c1c).
///         - {initImmutable}: the recipe cuts ONLY `DiamondLoupeFacet` (immutable-by-design diamonds) —
///           registers `IDiamondLoupe` alone, so `supportsInterface(0x1f931c1c)` stays false and tooling
///           can SEE the diamond is not upgradeable.
/// @dev Delegatecalled by {Diamond.initialize} inside the initializing window (stock diamond-lib
///      `DiamondInit` is NOT usable here: it unconditionally registers both flags AND initializes an
///      Ownable owner). Stateless; safe to share one deployed instance across recipes.
contract DiamondIntrospectionInit {
    /// @notice Registers the IDiamondCut + IDiamondLoupe ERC-165 flags (cut facet + loupe both cut).
    function initUpgradeable() external {
        DiamondLib.registerInterface();
    }

    /// @notice Registers ONLY the IDiamondLoupe ERC-165 flag (loupe cut, deliberately no cut facet).
    /// @dev `ERC165_MAP_ILOUPE_SLOT` is diamond-lib's precomputed map slot for `IDiamondLoupe`:
    ///      `keccak256(abi.encode(bytes4(0x48e2b093), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`
    ///      `= 0x8b4e92bdfe8926212c580d8c12b81d3807ee1d50462b0f735541a0bd64c0003c` (single `sstore`, per the
    ///      repo's `registerInterface` standard; the read path recomputes the keccak, so the guard tests'
    ///      `supportsInterface(0x48e2b093)` asserts verify the constant).
    function initImmutable() external {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ILOUPE_SLOT, true)
        }
    }
}
