// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RecipePlanLib} from "@lattice-script/lib/RecipePlanLib.sol";
import {RecipeFacet, RecipeSeam} from "@lattice-script/lib/RecipeSpec.sol";

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccountReleaseInventory} from "@lattice-script/lib/AccountReleaseInventory.sol";

/// @title AccountDeployBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Shared script-only account construction used by both account recipes and the release pipeline.
abstract contract AccountDeployBase is BaseDeploy {
    function _accountCuts(bool modular, string memory version) internal returns (FacetCut[] memory cuts) {
        return _materialize(_accountCutPlan(modular), new RecipeSeam[](0), version);
    }

    function _accountCutPlan(bool modular) internal pure returns (RecipeFacet[] memory facets) {
        string[] memory names = AccountReleaseInventory.facetNames(modular);
        facets = new RecipeFacet[](names.length);
        for (uint256 i; i < names.length; ++i) {
            facets[i] = RecipePlanLib.all(names[i]);
        }
    }

    function _accountInit(AccountReleaseInventory.Entry memory entry, string memory version)
        internal
        returns (address)
    {
        return _released(entry.initializer, entry.initializerArtifact, abi.encode(entry.entryPoint), version);
    }

    function _accountRelease(AccountReleaseInventory.Entry memory entry, string memory version)
        internal
        returns (FacetCut[] memory cuts, address init, address factory)
    {
        cuts = _accountCuts(entry.modular, version);
        (init, factory) = _accountContracts(entry, version, cuts);
    }

    /// @dev A release and its serializers reuse one blueprint per proxy kind, rather than per EntryPoint.
    function _accountBlueprints(string memory version) internal returns (FacetCut[][] memory blueprints) {
        blueprints = new FacetCut[][](2);
        blueprints[0] = _accountCuts(false, version);
        blueprints[1] = _accountCuts(true, version);
    }

    function _accountContracts(
        AccountReleaseInventory.Entry memory entry,
        string memory version,
        FacetCut[] memory cuts
    ) internal returns (address init, address factory) {
        init = _accountInit(entry, version);
        factory = _released(entry.factory, entry.factoryArtifact, abi.encode(cuts, init), version);
    }
}
