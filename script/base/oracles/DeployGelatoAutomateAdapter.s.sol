// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {GelatoAutomateAdapter} from "@lattice/oracles/GelatoAutomateAdapter.sol";
import {GelatoAutomateAdapterInit} from "@lattice/oracles/GelatoAutomateAdapterInit.sol";

/// @title DeployGelatoAutomateAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Gelato Automate adapter diamond: `ERC165Facet` + `AccessControl` +
///         `GelatoAutomateAdapter` + {GelatoAutomateAdapterInit}. The ONE source of truth for what a Gelato
///         Automate adapter diamond is, shared by production (`run --broadcast`) and the facet tests (which
///         build on {buildCuts}). `AccessControl` is part of the base recipe because
///         `setConfig`/`createTask`/`cancelTask` are `DEFAULT_ADMIN_ROLE`-gated; the Automate contract +
///         dedicated msg.sender are configured post-deploy via `setConfig`.
contract DeployGelatoAutomateAdapter is BaseDeploy {
    /// @notice Builds the Gelato Automate adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `setConfig`/`createTask`/`cancelTask`).
    /// @return cuts The facet cuts (ERC165 + AccessControl + GelatoAutomateAdapter).
    /// @return init The {GelatoAutomateAdapterInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new GelatoAutomateAdapter()), "GelatoAutomateAdapter");
        init = address(new GelatoAutomateAdapterInit());
        initCalldata = abi.encodeCall(GelatoAutomateAdapterInit.init, (admin));
    }

    /// @notice Deploys a Gelato Automate adapter diamond (broadcasting entrypoint for `forge script ...`).
    /// @param admin The Gelato Automate adapter admin.
    /// @return gelato The deployed Gelato Automate adapter diamond address.
    function run(address admin) external returns (address gelato) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        gelato = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
