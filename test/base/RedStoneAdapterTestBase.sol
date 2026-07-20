// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployRedStoneAdapter} from "@lattice-script/base/oracles/DeployRedStoneAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {RedStoneAdapter} from "@lattice/oracles/redstone/RedStoneAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title RedStoneAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for RedStone adapter facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployRedStoneAdapter} recipe (ERC165 +
///         AccessControl + RedStoneAdapter + {RedStoneAdapterInit}) and exposes a typed `adapter` handle — so
///         every feed call routes through the diamond's `delegatecall` dispatch, catching selector/storage/init
///         bugs a mock hides. The external `MockRedstoneAdapter` PriceFeedsAdapter stays a test fixture (it is NOT
///         the facet under test).
abstract contract RedStoneAdapterTestBase is Test, GetSelectors {
    DeployRedStoneAdapter internal deployer;
    address internal diamond; // the assembled RedStone adapter diamond
    RedStoneAdapter internal adapter; // typed handle on the diamond (feed calls dispatch through it)

    /// @notice Assembles the production RedStone adapter diamond with `admin` as the feed-registry admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed RedStone adapter diamond.
    function _deployRedStoneAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployRedStoneAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
