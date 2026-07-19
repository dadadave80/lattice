// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {GelatoAutomateAdapter} from "@lattice/oracles/gelato/GelatoAutomateAdapter.sol";
import {GelatoAutomateAdapterInit} from "@lattice/oracles/gelato/GelatoAutomateAdapterInit.sol";

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
    /// @return cuts The facet cuts (ERC165 + AccessControl + GelatoAutomateAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {GelatoAutomateAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new GelatoAutomateAdapter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new GelatoAutomateAdapterInit()), abi.encodeCall(GelatoAutomateAdapterInit.init, (admin))
        );
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
