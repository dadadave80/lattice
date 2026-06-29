// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {SafeDiamondCutLib} from "@lattice/governance/libraries/SafeDiamondCutLib.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {ISafeAuthority} from "@lattice/interfaces/governance/ISafeAuthority.sol";
import {ISafeDiamondCut} from "@lattice/interfaces/governance/ISafeDiamondCut.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";

/// @title SafeDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Stateless Diamond facet exposing the EIP-2535 `diamondCut` function at the canonical
///         selector `0x1f931c1c`, gated behind EmergencyStop + a pinned Gnosis Safe multisig. Drop-in
///         replacement for diamond-lib's owner-gated `DiamondCutFacet` in a Safe-governed deployment.
///         Also serves the append-only on-chain {IUpgradeRegistry} of every executed cut and a
///         self-administered Safe-rotation entry point. This is the INSTANT (no-delay) variant; use
///         {GovernedSafeDiamondCut} when a mandatory timelock between approval and execution is wanted.
/// @dev All logic lives in {SafeDiamondCutLib}. This contract is stateless and forwards its calls to the
///      library; inherit it in your Diamond to add Safe-gated upgrades. The registry getters plus the
///      frozen-selector / preview / verify / setSafe / safe surface are plain facet functions and are
///      NOT advertised as a distinct ERC-165 interface, so the facet's advertised id stays the canonical
///      cut selector `0x1f931c1c`.
///
///      AUTHORITY: the Safe collects M-of-N owner signatures off-chain and verifies the threshold
///      on-chain in `execTransaction`, then calls this facet. The facet does NOT re-verify signatures;
///      it trusts solely that `msg.sender == the pinned Safe`. The Safe MUST dispatch with
///      `operation = Call` (NEVER DelegateCall): a DelegateCall would run this code in the Safe's own
///      context, where `msg.sender` is whoever called the Safe, defeating the gate.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract SafeDiamondCut is ISafeDiamondCut, IUpgradeRegistry, IFrozenSelectors, IEmergencyCut {
    /// @inheritdoc ISafeDiamondCut
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata)
        external
        payable
        virtual
    {
        SafeDiamondCutLib.diamondCut(_diamondCut, _init, _calldata);
    }

    /// @inheritdoc ISafeAuthority
    function setSafe(address _newSafe) external virtual {
        SafeDiamondCutLib.setSafe(_newSafe);
    }

    /// @inheritdoc ISafeAuthority
    function safe() external view virtual returns (address) {
        return SafeDiamondCutLib.safe();
    }

    /// @inheritdoc IEmergencyCut
    function emergencyRemoveCut(FacetCut[] calldata _cuts) external virtual {
        SafeDiamondCutLib.emergencyRemoveCut(_cuts);
    }

    /// @inheritdoc IUpgradeRegistry
    function cutCount() external view virtual returns (uint256) {
        return SafeDiamondCutLib.cutCount();
    }

    /// @inheritdoc IUpgradeRegistry
    function getCutRecord(uint256 _version) external view virtual returns (IUpgradeRegistry.CutRecord memory) {
        return SafeDiamondCutLib.getCutRecord(_version);
    }

    /// @inheritdoc IFrozenSelectors
    function freezeSelectors(bytes4[] calldata _selectors) external virtual {
        SafeDiamondCutLib.freezeSelectors(_selectors);
    }

    /// @inheritdoc IFrozenSelectors
    function isSelectorFrozen(bytes4 _selector) external view virtual returns (bool) {
        return SafeDiamondCutLib.isSelectorFrozen(_selector);
    }

    /// @inheritdoc IFrozenSelectors
    function frozenSelectors() external view virtual returns (bytes4[] memory) {
        return SafeDiamondCutLib.frozenSelectors();
    }

    /// @inheritdoc IFrozenSelectors
    function previewCut(FacetCut[] calldata _cuts) external view virtual returns (bool ok, bytes4 offendingSelector) {
        return SafeDiamondCutLib.previewCut(_cuts);
    }

    /// @inheritdoc IFrozenSelectors
    function verifyInterfaceRegistered(bytes4 _interfaceId) external view virtual returns (bool) {
        return SafeDiamondCutLib.verifyInterfaceRegistered(_interfaceId);
    }
}
