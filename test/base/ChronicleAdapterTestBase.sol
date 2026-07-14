// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployChronicleAdapter} from "@lattice-script/base/oracles/DeployChronicleAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {ChronicleAdapter} from "@lattice/oracles/ChronicleAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title ChronicleAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Chronicle adapter facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployChronicleAdapter} recipe (ERC165 +
///         AccessControl + ChronicleAdapter + {ChronicleAdapterInit}) and exposes a typed `adapter` handle — so
///         every feed call routes through the diamond's `delegatecall` dispatch, catching selector/storage/init
///         bugs a mock hides. The external `MockChronicle` oracle stays a test fixture (it is NOT the facet under
///         test).
abstract contract ChronicleAdapterTestBase is Test, GetSelectors {
    DeployChronicleAdapter internal deployer;
    address internal diamond; // the assembled Chronicle adapter diamond
    ChronicleAdapter internal adapter; // typed handle on the diamond (feed calls dispatch through it)

    /// @notice Assembles the production Chronicle adapter diamond with `admin` as the feed-registry admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed Chronicle adapter diamond.
    function _deployChronicleAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployChronicleAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
