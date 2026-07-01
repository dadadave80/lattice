// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ChainlinkAutomationAdapter} from "@lattice/oracles/ChainlinkAutomationAdapter.sol";
import {ChainlinkAutomationAdapterInit} from "@lattice/oracles/ChainlinkAutomationAdapterInit.sol";

/// @title DeployChainlinkAutomationAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Chainlink Automation adapter diamond: `ERC165Facet` + `AccessControl` +
///         `ChainlinkAutomationAdapter` + {ChainlinkAutomationAdapterInit}. The ONE source of truth for what an
///         Automation adapter diamond is, shared by production (`run --broadcast`) and the facet tests (which
///         build on {buildCuts}). `AccessControl` is part of the base recipe because `setConfig` is
///         `DEFAULT_ADMIN_ROLE`-gated; the forwarder + interval are configured post-deploy via `setConfig`.
contract DeployChainlinkAutomationAdapter is BaseDeploy {
    /// @notice Builds the Automation adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `setConfig`).
    /// @return cuts The facet cuts (ERC165 + AccessControl + ChainlinkAutomationAdapter).
    /// @return init The {ChainlinkAutomationAdapterInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new ChainlinkAutomationAdapter()), "ChainlinkAutomationAdapter");
        init = address(new ChainlinkAutomationAdapterInit());
        initCalldata = abi.encodeCall(ChainlinkAutomationAdapterInit.init, (admin));
    }

    /// @notice Deploys an Automation adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The Automation adapter admin.
    /// @return automation The deployed Automation adapter diamond address.
    function run(address admin) external returns (address automation) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        automation = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
