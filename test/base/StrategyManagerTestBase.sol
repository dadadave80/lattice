// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployStrategyManager} from "@lattice-script/base/defi/DeployStrategyManager.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {StrategyManager} from "@lattice/defi/StrategyManager.sol";
import {Test} from "forge-std/Test.sol";

/// @title StrategyManagerTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for StrategyManager facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `_deployStrategyManager` assembles the production {DeployStrategyManager} recipe
///         (ERC165 + AccessControl + StrategyManager + {StrategyManagerInit}) and exposes a typed `mgr` handle —
///         so every manager call routes through the diamond's `delegatecall` dispatch, catching selector/storage/
///         init bugs a mock hides. Admin gating is enforced by the cut-in `AccessControl` facet;
///         `supportsInterface` by the cut-in `ERC165Facet`. The mock vault/strategy/token fixtures the tests
///         wire up stay in the test file — they are NOT the facet under test.
abstract contract StrategyManagerTestBase is Test, GetSelectors {
    DeployStrategyManager internal deployer;
    address internal diamond; // the assembled strategy-manager diamond
    StrategyManager internal mgr; // typed handle on the diamond (manager calls dispatch through it)

    /// @notice Assembles the production StrategyManager diamond with `admin` as the manager admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed strategy-manager diamond.
    function _deployStrategyManager(address admin) internal returns (address diamond_) {
        deployer = new DeployStrategyManager();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
