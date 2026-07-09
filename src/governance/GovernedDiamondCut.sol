// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {GovernedDiamondCutLib} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";

/// @title GovernedDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Stateless Diamond facet exposing the EIP-2535 `diamondCut` function at the canonical
///         selector `0x1f931c1c`, gated behind EmergencyStop + UPGRADE_EXECUTOR_ROLE. Drop-in
///         replacement for diamond-lib's owner-gated `DiamondCutFacet` in a governed deployment.
///         Also serves the append-only on-chain {IUpgradeRegistry} of every executed cut.
/// @dev All logic lives in {GovernedDiamondCutLib}. This contract is stateless and forwards its
///      calls to the library; inherit it in your Diamond to add governed upgrades. The registry
///      getters plus the frozen-selector / preview / verify surface are plain facet functions and are
///      NOT advertised as a distinct ERC-165 interface, so the facet's advertised id stays the
///      canonical cut selector `0x1f931c1c`.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract GovernedDiamondCut is IGovernedDiamondCut, IUpgradeRegistry, IFrozenSelectors, IEmergencyCut {
    /// @inheritdoc IGovernedDiamondCut
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata)
        external
        payable
        virtual
    {
        GovernedDiamondCutLib.diamondCut(_diamondCut, _init, _calldata);
    }

    /// @inheritdoc IEmergencyCut
    function emergencyRemoveCut(FacetCut[] calldata _cuts) external virtual {
        GovernedDiamondCutLib.emergencyRemoveCut(_cuts);
    }

    /// @inheritdoc IUpgradeRegistry
    function cutCount() external view virtual returns (uint256) {
        return GovernedDiamondCutLib.cutCount();
    }

    /// @inheritdoc IUpgradeRegistry
    function getCutRecord(uint256 _version) external view virtual returns (IUpgradeRegistry.CutRecord memory) {
        return GovernedDiamondCutLib.getCutRecord(_version);
    }

    /// @inheritdoc IFrozenSelectors
    function freezeSelectors(bytes4[] calldata _selectors) external virtual {
        GovernedDiamondCutLib.freezeSelectors(_selectors);
    }

    /// @inheritdoc IFrozenSelectors
    function isSelectorFrozen(bytes4 _selector) external view virtual returns (bool) {
        return GovernedDiamondCutLib.isSelectorFrozen(_selector);
    }

    /// @inheritdoc IFrozenSelectors
    function frozenSelectors() external view virtual returns (bytes4[] memory) {
        return GovernedDiamondCutLib.frozenSelectors();
    }

    /// @inheritdoc IFrozenSelectors
    function previewCut(FacetCut[] calldata _cuts) external view virtual returns (bool ok, bytes4 offendingSelector) {
        return GovernedDiamondCutLib.previewCut(_cuts);
    }

    /// @inheritdoc IFrozenSelectors
    function verifyInterfaceRegistered(bytes4 _interfaceId) external view virtual returns (bool) {
        return GovernedDiamondCutLib.verifyInterfaceRegistered(_interfaceId);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect GovernedDiamondCut methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `cutCount()` 0xaa982c45
    ///      `diamondCut((address,uint8,bytes4[])[],address,bytes)` 0x1f931c1c
    ///      `emergencyRemoveCut((address,uint8,bytes4[])[])` 0xc83542a6
    ///      `freezeSelectors(bytes4[])` 0x4487678f
    ///      `frozenSelectors()` 0x22cabf70
    ///      `getCutRecord(uint256)` 0x3adda78e
    ///      `isSelectorFrozen(bytes4)` 0xc8d8e114
    ///      `previewCut((address,uint8,bytes4[])[])` 0x35342750
    ///      `verifyInterfaceRegistered(bytes4)` 0x0746a956
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"aa982c451f931c1cc83542a64487678f22cabf703adda78ec8d8e114353427500746a956";
    }
}
