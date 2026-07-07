// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployMarketplaceZone} from "@lattice-script/base/tokens/DeployMarketplaceZone.s.sol";
import {Test} from "forge-std/Test.sol";

/// @title MarketplaceZoneTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for {MarketplaceZone} facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `_deployMarketplaceZone` assembles the production {DeployMarketplaceZone} recipe
///         (ERC165 + AccessControl + MarketplaceZone + {MarketplaceZoneInit}) so every zone hook
///         (`authorizeOrder`/`validateOrder`) and every admin/blocklist call routes through the diamond's
///         `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. No test-only helper facet is
///         needed — the zone's whole surface is production and already reachable through the diamond.
abstract contract MarketplaceZoneTestBase is Test, GetSelectors {
    DeployMarketplaceZone internal deployer;
    address internal diamond; // the assembled marketplace zone diamond

    /// @notice Assembles the production marketplace zone diamond with `admin` as the role admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed marketplace zone diamond.
    function _deployMarketplaceZone(address admin) internal returns (address diamond_) {
        deployer = new DeployMarketplaceZone();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
