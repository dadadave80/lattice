// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {PlonkVerifier} from "@lattice/privacy/PlonkVerifier.sol";
import {PlonkVerifierInit} from "@lattice/privacy/PlonkVerifierInit.sol";

/// @title DeployPlonkVerifier
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a PLONK verifier diamond: `ERC165Facet` + `PlonkVerifier` +
///         {PlonkVerifierInit}. The ONE source of truth for what a PLONK verifier diamond is, shared by
///         production (`run --broadcast`) and the facet tests (which build on {buildCuts}). The verifier is a
///         stateless, permissionless primitive, so there is NO `AccessControl` in the recipe.
contract DeployPlonkVerifier is BaseDeploy {
    /// @notice Builds the PLONK verifier diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @return cuts The facet cuts (ERC165 + PlonkVerifier).
    /// @return init The {PlonkVerifierInit} initializer address.
    /// @return initCalldata The `init()` calldata.
    function buildCuts() public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](2);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new PlonkVerifier()));
        init = address(new PlonkVerifierInit());
        initCalldata = abi.encodeCall(PlonkVerifierInit.init, ());
    }

    /// @notice Deploys a PLONK verifier diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return verifier The deployed PLONK verifier diamond address.
    function run() external returns (address verifier) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts();
        verifier = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
