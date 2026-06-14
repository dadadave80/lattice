// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {GovernedDiamondCutLib} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {IFrozenSelectors} from "@lattice/interfaces/IFrozenSelectors.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/IGovernedDiamondCut.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/IUpgradeRegistry.sol";

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
contract GovernedDiamondCut is IGovernedDiamondCut, IUpgradeRegistry, IFrozenSelectors {
    /// @inheritdoc IGovernedDiamondCut
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata)
        external
        payable
        virtual
    {
        GovernedDiamondCutLib.diamondCut(_diamondCut, _init, _calldata);
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
}
