// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployPrivateVoting} from "@lattice-script/base/privacy/DeployPrivateVoting.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {PrivateVoting} from "@lattice/privacy/PrivateVoting.sol";
import {Semaphore} from "@lattice/privacy/Semaphore.sol";
import {Test} from "forge-std/Test.sol";

/// @title PrivateVotingTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for PrivateVoting facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployPrivateVoting} recipe (ERC165 + Semaphore + PrivateVoting
///         + {PrivateVotingInit}) — BOTH the membership (`Semaphore`) and tally (`PrivateVoting`) facets are cut
///         into ONE diamond — and exposes typed `voting` and `semaphore` handles onto the same address, so every
///         call routes through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock
///         hides. The off-chain `SemaphoreVerifier` and its proofs stay test fixtures (NOT the facet under test).
abstract contract PrivateVotingTestBase is Test, GetSelectors {
    DeployPrivateVoting internal deployer;
    address internal diamond; // the assembled private-voting diamond (Semaphore + PrivateVoting)
    PrivateVoting internal voting; // typed handle on the diamond (poll/vote calls dispatch through it)
    Semaphore internal semaphore; // typed handle on the SAME diamond (group/membership calls dispatch through it)

    /// @notice Assembles the production PrivateVoting diamond.
    /// @param verifier The {ISemaphoreVerifier} contract address.
    /// @return diamond_ The deployed private-voting diamond.
    function _deployPrivateVoting(address verifier) internal returns (address diamond_) {
        deployer = new DeployPrivateVoting();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(verifier);

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
