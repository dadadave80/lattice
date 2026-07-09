// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Groth16Verifier} from "@lattice/privacy/Groth16Verifier.sol";
import {Groth16VerifierInit} from "@lattice/privacy/Groth16VerifierInit.sol";

/// @title DeployGroth16Verifier
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Groth16 verifier diamond: `ERC165Facet` + `Groth16Verifier` +
///         {Groth16VerifierInit}. The ONE source of truth for what a Groth16 verifier diamond is, shared by
///         production (`run --broadcast`) and the facet tests (which build on {buildCuts}). The verifier is a
///         stateless, permissionless primitive, so there is NO `AccessControl` in the recipe.
contract DeployGroth16Verifier is BaseDeploy {
    /// @notice Builds the Groth16 verifier diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @return cuts The facet cuts (ERC165 + Groth16Verifier).
    /// @return init The {Groth16VerifierInit} initializer address.
    /// @return initCalldata The `init()` calldata.
    function buildCuts() public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](2);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new Groth16Verifier()));
        init = address(new Groth16VerifierInit());
        initCalldata = abi.encodeCall(Groth16VerifierInit.init, ());
    }

    /// @notice Deploys a Groth16 verifier diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return verifier The deployed Groth16 verifier diamond address.
    function run() external returns (address verifier) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts();
        verifier = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
