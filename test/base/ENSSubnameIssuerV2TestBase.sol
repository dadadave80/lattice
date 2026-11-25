// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployENSSubnameIssuerV2} from "@lattice-script/base/ens/DeployENSSubnameIssuerV2.s.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IENSSubnameIssuerV2} from "@lattice/interfaces/ens/IENSSubnameIssuerV2.sol";
import {Test} from "forge-std/Test.sol";

abstract contract ENSSubnameIssuerV2TestBase is Test {
    DeployENSSubnameIssuerV2 internal deployer;
    IENSSubnameIssuerV2 internal subnameIssuer;
    address internal diamond;

    function _deployENSSubnameIssuerV2(address admin, address helper) internal {
        deployer = new DeployENSSubnameIssuerV2();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, helper);
        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond = address(d);
        subnameIssuer = IENSSubnameIssuerV2(diamond);
    }
}
