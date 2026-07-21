// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC5564Announcer} from "@lattice-script/base/privacy/DeployERC5564Announcer.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {ERC5564Announcer} from "@lattice/privacy/ERC5564Announcer.sol";
import {Test} from "forge-std/Test.sol";

/// @title ERC5564AnnouncerTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ERC-5564 announcer facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployERC5564Announcer} recipe (ERC165 +
///         ERC5564Announcer + {ERC5564AnnouncerInit}) and exposes a typed `announcer` handle — so every `announce`
///         routes through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides.
///         The announcer is permissionless, so no AccessControl facet is cut.
abstract contract ERC5564AnnouncerTestBase is Test, GetSelectors {
    DeployERC5564Announcer internal deployer;
    address internal diamond; // the assembled announcer diamond
    ERC5564Announcer internal announcer; // typed handle on the diamond (announce dispatches through it)

    /// @notice Assembles the production ERC-5564 announcer diamond.
    /// @return diamond_ The deployed announcer diamond.
    function _deployERC5564Announcer() internal returns (address diamond_) {
        deployer = new DeployERC5564Announcer();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts();

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
