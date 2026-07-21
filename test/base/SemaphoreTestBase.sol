// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeploySemaphore} from "@lattice-script/base/privacy/DeploySemaphore.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {Semaphore} from "@lattice/privacy/Semaphore.sol";
import {Test} from "forge-std/Test.sol";

/// @title SemaphoreTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Semaphore facet tests that exercise a REAL {Diamond} rather than a flattened inheritance mock.
///         `setUp` assembles the production {DeploySemaphore} recipe (ERC165 + AccessControl + Semaphore +
///         {SemaphoreInit}) and exposes a typed `semaphore` handle — so every membership/signaling call routes
///         through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The
///         off-chain `SemaphoreVerifier` and its proof stay test fixtures (they are NOT the facet under test).
abstract contract SemaphoreTestBase is Test, GetSelectors {
    DeploySemaphore internal deployer;
    address internal diamond; // the assembled Semaphore diamond
    Semaphore internal semaphore; // typed handle on the diamond (membership/proof calls dispatch through it)

    /// @notice Assembles the production Semaphore diamond with `admin` as the Semaphore admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `setVerifier`).
    /// @param verifier The {ISemaphoreVerifier} contract address.
    /// @return diamond_ The deployed Semaphore diamond.
    function _deploySemaphore(address admin, address verifier) internal returns (address diamond_) {
        deployer = new DeploySemaphore();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, verifier);

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
