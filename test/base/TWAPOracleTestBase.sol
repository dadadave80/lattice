// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployTWAPOracle} from "@lattice-script/base/oracles/DeployTWAPOracle.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {TWAPOracle} from "@lattice/oracles/TWAPOracle.sol";
import {Test} from "forge-std/Test.sol";

/// @title TWAPOracleTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for TWAPOracle facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `_deployTWAPOracle` assembles the production {DeployTWAPOracle} recipe (ERC165 + AccessControl +
///         TWAPOracle + {TWAPOracleInit}) and exposes a typed `oracle` handle — so every oracle call routes
///         through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides.
///         Pair registration is gated by the cut-in `AccessControl` facet; `supportsInterface` by the cut-in
///         `ERC165Facet`. The external Uniswap-V2 pair mock the oracle reads stays in the test file — it is NOT
///         the facet under test.
abstract contract TWAPOracleTestBase is Test, GetSelectors {
    DeployTWAPOracle internal deployer;
    address internal diamond; // the assembled TWAP oracle diamond
    TWAPOracle internal oracle; // typed handle on the diamond (oracle calls dispatch through it)

    /// @notice Assembles the production TWAPOracle diamond with `admin` as the oracle admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed TWAP oracle diamond.
    function _deployTWAPOracle(address admin) internal returns (address diamond_) {
        deployer = new DeployTWAPOracle();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
