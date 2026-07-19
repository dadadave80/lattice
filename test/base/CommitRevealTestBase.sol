// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployCommitReveal} from "@lattice-script/base/privacy/DeployCommitReveal.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {CommitReveal} from "@lattice/privacy/CommitReveal.sol";
import {Test} from "forge-std/Test.sol";

/// @title CommitRevealTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for CommitReveal facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployCommitReveal} recipe (ERC165 + CommitReveal +
///         {CommitRevealInit}) and exposes a typed `cr` handle — so every commit/reveal call routes through the
///         diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. No AccessControl
///         and no test-only helper facet: the primitive is permissionless and the tests drive public facet
///         functions only.
abstract contract CommitRevealTestBase is Test, GetSelectors {
    DeployCommitReveal internal deployer;
    address internal diamond; // the assembled commit-reveal diamond
    CommitReveal internal cr; // typed handle on the diamond (commit/reveal calls dispatch through it)

    /// @notice Assembles the production CommitReveal diamond.
    /// @return diamond_ The deployed commit-reveal diamond.
    function _deployCommitReveal() internal returns (address diamond_) {
        deployer = new DeployCommitReveal();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts();

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
