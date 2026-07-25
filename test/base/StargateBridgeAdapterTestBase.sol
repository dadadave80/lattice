// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployStargateBridgeAdapter} from "@lattice-script/base/crosschain/DeployStargateBridgeAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {Test} from "forge-std/Test.sol";

/// @title StargateBridgeAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Stargate token-bridge adapter facet tests that exercise a REAL {Diamond} rather than a
///         flattened inheritance mock. `_deployStargateBridgeAdapter` assembles the production
///         {DeployStargateBridgeAdapter} recipe (ERC165 + AccessControl + StargateBridgeAdapter +
///         {StargateBridgeAdapterInit}) with `admin` seeded as `DEFAULT_ADMIN_ROLE` — so every send / admin /
///         read call routes through the diamond's `delegatecall` dispatch, catching selector/storage/init
///         bugs a mock hides. The external `MockStargatePool` stays a test fixture (it is NOT the facet under
///         test); the eid map and per-token pools are registered by the admin in each test's setup, exactly
///         as in production.
abstract contract StargateBridgeAdapterTestBase is Test, GetSelectors {
    DeployStargateBridgeAdapter internal deployer;

    /// @notice Assembles the production Stargate adapter diamond with `admin` as the adapter admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed Stargate adapter diamond.
    function _deployStargateBridgeAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployStargateBridgeAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
