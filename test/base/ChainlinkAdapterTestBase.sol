// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployChainlinkAdapter} from "@lattice-script/base/oracles/DeployChainlinkAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {ChainlinkAdapter} from "@lattice/oracles/chainlink/ChainlinkAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title ChainlinkAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Chainlink adapter facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployChainlinkAdapter} recipe (ERC165 +
///         AccessControl + ChainlinkAdapter + {ChainlinkAdapterInit}) and exposes a typed `adapter` handle — so
///         every feed call routes through the diamond's `delegatecall` dispatch, catching selector/storage/init
///         bugs a mock hides. The external `MockAggregator` feeds stay test fixtures (they are NOT the facet
///         under test).
abstract contract ChainlinkAdapterTestBase is Test, GetSelectors {
    DeployChainlinkAdapter internal deployer;
    address internal diamond; // the assembled Chainlink adapter diamond
    ChainlinkAdapter internal adapter; // typed handle on the diamond (feed calls dispatch through it)

    /// @notice Assembles the production Chainlink adapter diamond with `admin` as the feed-registry admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed Chainlink adapter diamond.
    function _deployChainlinkAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployChainlinkAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
