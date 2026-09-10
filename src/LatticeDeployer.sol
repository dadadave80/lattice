// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {Lattice} from "@lattice/Lattice.sol";

/// @title LatticeDeployer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Deploys and initializes a {Lattice} atomically.
contract LatticeDeployer {
    function deploy(FacetCut[] calldata cuts, address init, bytes calldata initCalldata)
        external
        returns (address diamond)
    {
        Lattice lattice = new Lattice();
        lattice.initialize(cuts, init, initCalldata);
        diamond = address(lattice);
    }
}
