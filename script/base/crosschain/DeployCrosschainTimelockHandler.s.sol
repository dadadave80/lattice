// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {CrosschainTimelockHandler} from "@lattice/crosschain/CrosschainTimelockHandler.sol";
import {CrosschainTimelockHandlerInit} from "@lattice/crosschain/CrosschainTimelockHandlerInit.sol";
import {TimelockController} from "@lattice/governance/TimelockController.sol";

/// @title DeployCrosschainTimelockHandler
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a cross-chain governance diamond: `ERC165Facet` + `AccessControl` +
///         `CrosschainLink` + `TimelockController` + `CrosschainTimelockHandler` + {CrosschainTimelockHandlerInit}.
///         The ONE source of truth for what a cross-chain timelock diamond is, shared by production
///         (`run --broadcast`) and the facet tests (which build on {buildCuts}). The Diamond itself is the sole
///         timelock proposer, so only the authenticated cross-chain handler can schedule operations.
contract DeployCrosschainTimelockHandler is BaseDeploy {
    /// @notice Builds the cross-chain timelock diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (timelock + link/handler registry admin).
    /// @param minDelay The timelock's minimum operation delay.
    /// @return cuts The facet cuts (ERC165 + AccessControl + CrosschainLink + TimelockController + handler).
    /// @return init The {CrosschainTimelockHandlerInit} initializer address.
    /// @return initCalldata The `init(admin, minDelay)` calldata.
    function buildCuts(address admin, uint256 minDelay)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new CrosschainLink()), "CrosschainLink");
        cuts[3] = _cut(address(new TimelockController()), "TimelockController");
        cuts[4] = _cut(address(new CrosschainTimelockHandler()), "CrosschainTimelockHandler");
        init = address(new CrosschainTimelockHandlerInit());
        initCalldata = abi.encodeCall(CrosschainTimelockHandlerInit.init, (admin, minDelay));
    }

    /// @notice Deploys a cross-chain governance diamond (broadcasting entrypoint for `forge script ...`).
    /// @param admin The timelock + registry admin.
    /// @param minDelay The timelock minimum delay.
    /// @return gov The deployed cross-chain governance diamond address.
    function run(address admin, uint256 minDelay) external returns (address gov) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, minDelay);
        gov = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
