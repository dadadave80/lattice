// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {CommitReveal} from "@lattice/privacy/CommitReveal.sol";
import {CommitRevealInit} from "@lattice/privacy/CommitRevealInit.sol";

/// @title DeployCommitReveal
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a CommitReveal diamond: `ERC165Facet` + `CommitReveal` + {CommitRevealInit}.
///         The ONE source of truth for what a commit-reveal diamond is, shared by production (`run --broadcast`)
///         and the facet tests (which build on {buildCuts}). The primitive is permissionless (anyone may
///         commit/reveal their own), so there is NO `AccessControl` in the recipe.
contract DeployCommitReveal is BaseDeploy {
    /// @notice Builds the CommitReveal diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @return cuts The facet cuts (ERC165 + CommitReveal).
    /// @return init The {CommitRevealInit} initializer address.
    /// @return initCalldata The `init()` calldata.
    function buildCuts() public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](2);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new CommitReveal()), "CommitReveal");
        init = address(new CommitRevealInit());
        initCalldata = abi.encodeCall(CommitRevealInit.init, ());
    }

    /// @notice Deploys a CommitReveal diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return commitReveal The deployed commit-reveal diamond address.
    function run() external returns (address commitReveal) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts();
        commitReveal = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
