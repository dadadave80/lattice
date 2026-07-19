// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAggregatorExecAdapter} from "@lattice-script/base/defi/DeployAggregatorExecAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {Test} from "forge-std/Test.sol";

/// @title AggregatorExecAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for aggregator execution adapter facet tests that exercise a REAL {Diamond} rather than a
///         flattened inheritance mock. `_deployAggregatorExecAdapter` assembles the production
///         {DeployAggregatorExecAdapter} recipe (ERC165 + AccessControl + AggregatorExecAdapter +
///         {AggregatorExecAdapterInit}) — so every allow-list / execute call routes through the diamond's
///         `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The external
///         `MockAggregator` and `MockERC20` stay test fixtures (they are NOT the facet under test). The
///         zero-admin init guard is exercised by calling `buildCuts(address(0))` inside `vm.expectRevert`.
abstract contract AggregatorExecAdapterTestBase is Test, GetSelectors {
    DeployAggregatorExecAdapter internal deployer;

    /// @notice Assembles the production aggregator execution diamond with `admin` as the adapter admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed aggregator execution diamond.
    function _deployAggregatorExecAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployAggregatorExecAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
