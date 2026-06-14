// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {GovernedDiamondCutLib} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/IGovernedDiamondCut.sol";

/// @title GovernedDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Stateless Diamond facet exposing the EIP-2535 `diamondCut` function at the canonical
///         selector `0x1f931c1c`, gated behind EmergencyStop + UPGRADE_EXECUTOR_ROLE. Drop-in
///         replacement for diamond-lib's owner-gated `DiamondCutFacet` in a governed deployment.
/// @dev All logic lives in {GovernedDiamondCutLib}. This contract is stateless and forwards its
///      single external call to the library; inherit it in your Diamond to add governed upgrades.
contract GovernedDiamondCut is IGovernedDiamondCut {
    /// @inheritdoc IGovernedDiamondCut
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata)
        external
        payable
        virtual
    {
        GovernedDiamondCutLib.diamondCut(_diamondCut, _init, _calldata);
    }
}
