// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {GovernedSafeDiamondCutLib} from "@lattice/governance/libraries/GovernedSafeDiamondCutLib.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {IGovernedSafeDiamondCut} from "@lattice/interfaces/governance/IGovernedSafeDiamondCut.sol";
import {ISafeAuthority} from "@lattice/interfaces/governance/ISafeAuthority.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";

/// @title GovernedSafeDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Stateless Diamond facet exposing a Safe-multisig-gated EIP-2535 cut WITH a self-contained
///         timelock: the pinned Safe `scheduleCut`s an upgrade, it matures past `minDelay`, and only
///         then can the Safe `executeCut` it; a still-pending operation can be `cancelCut`-ed. No
///         external Governor/TimelockController is required. Also serves the append-only on-chain
///         {IUpgradeRegistry}, the frozen-selector protection layer, the guardian-gated emergency
///         removal escape hatch, and self-administered Safe-rotation / min-delay setters. Unlike
///         {SafeDiamondCut} it deliberately does NOT serve the synchronous cut selector `0x1f931c1c`
///         (every cut is delayed).
/// @dev All logic lives in {GovernedSafeDiamondCutLib}. This contract is stateless and forwards its
///      calls to the library; inherit it in your Diamond to add Safe-gated, timelocked upgrades. The
///      scheduling surface (`scheduleCut`/`executeCut`/`cancelCut` + timelock views) is a genuinely new
///      interface advertised via ERC-165 id `0xacb1aeb6`; the registry / frozen / emergency / rotation
///      surface are plain facet functions sharing the same module slot.
///
///      AUTHORITY: the Safe collects M-of-N owner signatures off-chain and verifies the threshold
///      on-chain in `execTransaction`, then calls this facet. The facet does NOT re-verify signatures;
///      it trusts solely that `msg.sender == the pinned Safe`. The Safe MUST dispatch with
///      `operation = Call` (NEVER DelegateCall): a DelegateCall would run this code in the Safe's own
///      context, where `msg.sender` is whoever called the Safe, defeating the gate.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract GovernedSafeDiamondCut is
    IGovernedSafeDiamondCut,
    ISafeAuthority,
    IUpgradeRegistry,
    IFrozenSelectors,
    IEmergencyCut
{
    /// @inheritdoc IGovernedSafeDiamondCut
    function scheduleCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata, bytes32 _salt)
        external
        virtual
        returns (bytes32 id)
    {
        return GovernedSafeDiamondCutLib.scheduleCut(_diamondCut, _init, _calldata, _salt);
    }

    /// @inheritdoc IGovernedSafeDiamondCut
    function executeCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata, bytes32 _salt)
        external
        payable
        virtual
    {
        GovernedSafeDiamondCutLib.executeCut(_diamondCut, _init, _calldata, _salt);
    }

    /// @inheritdoc IGovernedSafeDiamondCut
    function cancelCut(bytes32 _id) external virtual {
        GovernedSafeDiamondCutLib.cancelCut(_id);
    }

    /// @inheritdoc IGovernedSafeDiamondCut
    function getTimestamp(bytes32 _id) external view virtual returns (uint256) {
        return GovernedSafeDiamondCutLib.getTimestamp(_id);
    }

    /// @inheritdoc IGovernedSafeDiamondCut
    function isOperationPending(bytes32 _id) external view virtual returns (bool) {
        return GovernedSafeDiamondCutLib.isOperationPending(_id);
    }

    /// @inheritdoc IGovernedSafeDiamondCut
    function isOperationReady(bytes32 _id) external view virtual returns (bool) {
        return GovernedSafeDiamondCutLib.isOperationReady(_id);
    }

    /// @inheritdoc IGovernedSafeDiamondCut
    function isOperationDone(bytes32 _id) external view virtual returns (bool) {
        return GovernedSafeDiamondCutLib.isOperationDone(_id);
    }

    /// @inheritdoc IGovernedSafeDiamondCut
    function minDelay() external view virtual returns (uint256) {
        return GovernedSafeDiamondCutLib.minDelay();
    }

    /// @notice Sets the minimum timelock delay (seconds). Self-administered: callable only by the
    ///         pinned Safe. Affects operations scheduled after the change.
    /// @param _newDelay The new minimum delay (seconds).
    function setMinDelay(uint256 _newDelay) external virtual {
        GovernedSafeDiamondCutLib.setMinDelay(_newDelay);
    }

    /// @inheritdoc ISafeAuthority
    function setSafe(address _newSafe) external virtual {
        GovernedSafeDiamondCutLib.setSafe(_newSafe);
    }

    /// @inheritdoc ISafeAuthority
    function safe() external view virtual returns (address) {
        return GovernedSafeDiamondCutLib.safe();
    }

    /// @inheritdoc IEmergencyCut
    function emergencyRemoveCut(FacetCut[] calldata _cuts) external virtual {
        GovernedSafeDiamondCutLib.emergencyRemoveCut(_cuts);
    }

    /// @inheritdoc IUpgradeRegistry
    function cutCount() external view virtual returns (uint256) {
        return GovernedSafeDiamondCutLib.cutCount();
    }

    /// @inheritdoc IUpgradeRegistry
    function getCutRecord(uint256 _version) external view virtual returns (IUpgradeRegistry.CutRecord memory) {
        return GovernedSafeDiamondCutLib.getCutRecord(_version);
    }

    /// @inheritdoc IFrozenSelectors
    function freezeSelectors(bytes4[] calldata _selectors) external virtual {
        GovernedSafeDiamondCutLib.freezeSelectors(_selectors);
    }

    /// @inheritdoc IFrozenSelectors
    function isSelectorFrozen(bytes4 _selector) external view virtual returns (bool) {
        return GovernedSafeDiamondCutLib.isSelectorFrozen(_selector);
    }

    /// @inheritdoc IFrozenSelectors
    function frozenSelectors() external view virtual returns (bytes4[] memory) {
        return GovernedSafeDiamondCutLib.frozenSelectors();
    }

    /// @inheritdoc IFrozenSelectors
    function previewCut(FacetCut[] calldata _cuts) external view virtual returns (bool ok, bytes4 offendingSelector) {
        return GovernedSafeDiamondCutLib.previewCut(_cuts);
    }

    /// @inheritdoc IFrozenSelectors
    function verifyInterfaceRegistered(bytes4 _interfaceId) external view virtual returns (bool) {
        return GovernedSafeDiamondCutLib.verifyInterfaceRegistered(_interfaceId);
    }
}
