// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployENSResolverV2} from "@lattice-script/base/ens/DeployENSResolverV2.s.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IENSResolverV2} from "@lattice/interfaces/ens/IENSResolverV2.sol";
import {Test} from "forge-std/Test.sol";

/// @title ENSResolverV2TestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Assembles the released recipe, exercising dispatch, initialization and role management together.
abstract contract ENSResolverV2TestBase is Test {
    function _deployENSResolverV2(address admin, address proxy) internal returns (IENSResolverV2) {
        (FacetCut[] memory cuts, address init, bytes memory data) = new DeployENSResolverV2().buildCuts(admin, proxy);
        Lattice diamond = new Lattice();
        diamond.initialize(cuts, init, data);
        return IENSResolverV2(address(diamond));
    }
}
