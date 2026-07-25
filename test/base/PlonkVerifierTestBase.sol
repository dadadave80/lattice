// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployPlonkVerifier} from "@lattice-script/base/privacy/DeployPlonkVerifier.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {PlonkVerifier} from "@lattice/privacy/PlonkVerifier.sol";
import {Test} from "forge-std/Test.sol";

/// @title PlonkVerifierTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for PLONK verifier facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployPlonkVerifier} recipe (ERC165 + PlonkVerifier +
///         {PlonkVerifierInit}) and exposes a typed `verifier` handle — so every `verifyProof` call routes through
///         the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The off-chain
///         proof/vkey stay test fixtures (they are NOT the facet under test).
abstract contract PlonkVerifierTestBase is Test, GetSelectors {
    DeployPlonkVerifier internal deployer;
    address internal diamond; // the assembled PLONK verifier diamond
    PlonkVerifier internal verifier; // typed handle on the diamond (verifyProof dispatches through it)

    /// @notice Assembles the production PLONK verifier diamond.
    /// @return diamond_ The deployed PLONK verifier diamond.
    function _deployPlonkVerifier() internal returns (address diamond_) {
        deployer = new DeployPlonkVerifier();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts();

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
