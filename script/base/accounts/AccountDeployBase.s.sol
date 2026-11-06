// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccountReleaseInventory} from "@lattice-script/lib/AccountReleaseInventory.sol";

/// @title AccountDeployBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Shared script-only account construction used by both account recipes and the release pipeline.
abstract contract AccountDeployBase is BaseDeploy {
    function _accountCuts(bool modular, string memory version) internal returns (FacetCut[] memory cuts) {
        string[] memory names = AccountReleaseInventory.facetNames(modular);
        cuts = new FacetCut[](names.length);
        for (uint256 i; i < names.length; ++i) {
            cuts[i] = _cut(_facet(names[i], version));
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
        init = _accountInit(entry, version);
        factory = _released(entry.factory, entry.factoryArtifact, abi.encode(cuts, init), version);
    }
}
