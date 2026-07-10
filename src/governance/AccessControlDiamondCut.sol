// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AccessControlDiamondCutLib} from "@lattice/governance/libraries/AccessControlDiamondCutLib.sol";
import {IAccessControlDiamondCut} from "@lattice/interfaces/governance/IAccessControlDiamondCut.sol";

/// @title AccessControlDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Stateless Diamond facet exposing the EIP-2535 `diamondCut` function at the canonical
///         selector `0x1f931c1c`, gated behind EmergencyStop + `DEFAULT_ADMIN_ROLE`. Drop-in
///         replacement for diamond-lib's owner-gated `DiamondCutFacet` in an ADMIN-OWNED deployment:
///         the module admin every Lattice recipe already seeds is also the upgrade authority — one
///         authority model, no parallel Ownable owner to initialize or track.
/// @dev All logic lives in {AccessControlDiamondCutLib}. This contract is stateless and forwards its
///      single call to the library. Never cut this facet AND another `diamondCut`-carrying facet
///      ({GovernedDiamondCut}, {SafeDiamondCut}, diamond-lib's `DiamondCutFacet`) into the same
///      diamond — they all own selector `0x1f931c1c`. For governance-held diamonds (upgrade registry,
///      frozen selectors, guardian escape hatch) cut {GovernedDiamondCut} instead.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract AccessControlDiamondCut is IAccessControlDiamondCut {
    /// @inheritdoc IAccessControlDiamondCut
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata)
        external
        payable
        virtual
    {
        AccessControlDiamondCutLib.diamondCut(_diamondCut, _init, _calldata);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect AccessControlDiamondCut methodIdentifiers` (alphabetical by signature); kept in
    ///      exact parity by ExportSelectorsParityTest. Chunks:
    ///      `diamondCut((address,uint8,bytes4[])[],address,bytes)` 0x1f931c1c
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"1f931c1c";
    }
}
