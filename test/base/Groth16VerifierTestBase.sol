// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployGroth16Verifier} from "@lattice-script/base/privacy/DeployGroth16Verifier.s.sol";
import {Groth16Verifier} from "@lattice/privacy/Groth16Verifier.sol";
import {Test} from "forge-std/Test.sol";

/// @title Groth16VerifierTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Groth16 verifier facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployGroth16Verifier} recipe (ERC165 +
///         Groth16Verifier + {Groth16VerifierInit}) and exposes a typed `verifier` handle — so every
///         `verifyProof` call routes through the diamond's `delegatecall` dispatch, catching selector/storage/init
///         bugs a mock hides. The off-chain proof/vkey stay test fixtures (they are NOT the facet under test).
abstract contract Groth16VerifierTestBase is Test, GetSelectors {
    DeployGroth16Verifier internal deployer;
    address internal diamond; // the assembled Groth16 verifier diamond
    Groth16Verifier internal verifier; // typed handle on the diamond (verifyProof dispatches through it)

    /// @notice Assembles the production Groth16 verifier diamond.
    /// @return diamond_ The deployed Groth16 verifier diamond.
    function _deployGroth16Verifier() internal returns (address diamond_) {
        deployer = new DeployGroth16Verifier();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts();

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
