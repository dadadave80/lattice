// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployCrosschainTimelockHandler} from "@lattice-script/base/crosschain/DeployCrosschainTimelockHandler.s.sol";
import {Test} from "forge-std/Test.sol";

/// @title CrosschainTimelockHandlerTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for CrosschainTimelockHandler facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `_deployCrosschainTimelockHandler` assembles the production
///         {DeployCrosschainTimelockHandler} recipe (ERC165 + AccessControl + CrosschainLink + TimelockController
///         + CrosschainTimelockHandler + {CrosschainTimelockHandlerInit}) — so every governance call routes
///         through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The
///         external ERC-7786 gateway + timelock-target mocks stay test fixtures (they are NOT the facet under
///         test). The Diamond itself is the sole timelock proposer, so only the authenticated cross-chain handler
///         can schedule operations.
abstract contract CrosschainTimelockHandlerTestBase is Test, GetSelectors {
    DeployCrosschainTimelockHandler internal deployer;

    /// @notice Assembles the production cross-chain governance diamond with `admin` as the registry/timelock admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param minDelay The timelock minimum operation delay.
    /// @return diamond_ The deployed cross-chain governance diamond.
    function _deployCrosschainTimelockHandler(address admin, uint256 minDelay) internal returns (address diamond_) {
        deployer = new DeployCrosschainTimelockHandler();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, minDelay);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
