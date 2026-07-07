// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {PrivateVoting} from "@lattice/privacy/PrivateVoting.sol";
import {PrivateVotingInit} from "@lattice/privacy/PrivateVotingInit.sol";
import {Semaphore} from "@lattice/privacy/Semaphore.sol";

/// @title DeployPrivateVoting
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an anonymous-voting diamond: `ERC165Facet` + `Semaphore` + `PrivateVoting`
///         + {PrivateVotingInit}. The ONE source of truth for what a private-voting diamond is, shared by
///         production (`run --broadcast`) and the facet tests (which build on {buildCuts}). PrivateVoting layers
///         1p1v tallying on top of the `Semaphore` membership facet, so BOTH facets are cut in. Poll and group
///         admin are per-group (set by `createGroup`), so there is NO `AccessControl` in the recipe. The off-chain
///         proof `verifier` is an external dependency address (its `ISemaphoreVerifier` mock is a test fixture).
contract DeployPrivateVoting is BaseDeploy {
    /// @notice Builds the PrivateVoting diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param verifier The {ISemaphoreVerifier} contract address used to check the anonymous vote proofs.
    /// @return cuts The facet cuts (ERC165 + Semaphore + PrivateVoting).
    /// @return init The {PrivateVotingInit} initializer address.
    /// @return initCalldata The `init(verifier)` calldata.
    function buildCuts(address verifier)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new Semaphore()), "Semaphore");
        cuts[2] = _cut(address(new PrivateVoting()), "PrivateVoting");
        init = address(new PrivateVotingInit());
        initCalldata = abi.encodeCall(PrivateVotingInit.init, (verifier));
    }

    /// @notice Deploys a PrivateVoting diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param verifier The {ISemaphoreVerifier} contract address.
    /// @return voting The deployed private-voting diamond address.
    function run(address verifier) external returns (address voting) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(verifier);
        voting = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
