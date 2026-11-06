// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployStargateBusBridgeAdapter} from "@lattice-script/base/crosschain/DeployStargateBusBridgeAdapter.s.sol";
import {StargateBridgeAdapterTestBase} from "@lattice-test/base/StargateBridgeAdapterTestBase.sol";
import {Lattice} from "@lattice/Lattice.sol";

/// @title StargateBusBridgeAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Real proxy setup through the optional production recipe, retaining the old taxi-only setup for upgrades.
abstract contract StargateBusBridgeAdapterTestBase is StargateBridgeAdapterTestBase {
    function _deployStargateBusBridgeAdapter(address admin) internal returns (address diamond_) {
        (FacetCut[] memory cuts, address init, bytes memory data) =
            new DeployStargateBusBridgeAdapter().buildCuts(admin);
        Lattice diamond = new Lattice();
        diamond.initialize(cuts, init, data);
        return address(diamond);
    }
}
