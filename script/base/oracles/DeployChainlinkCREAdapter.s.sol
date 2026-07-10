// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ChainlinkCREAdapter} from "@lattice/oracles/ChainlinkCREAdapter.sol";
import {ChainlinkCREAdapterInit} from "@lattice/oracles/ChainlinkCREAdapterInit.sol";

/// @title DeployChainlinkCREAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Chainlink CRE adapter diamond: `ERC165Facet` + `AccessControl` +
///         `ChainlinkCREAdapter` + {ChainlinkCREAdapterInit}. The ONE source of truth for what a CRE adapter
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because `setForwarder`/`setWorkflow` are
///         `DEFAULT_ADMIN_ROLE`-gated; the forwarder + workflow allowlist are configured post-deploy.
contract DeployChainlinkCREAdapter is BaseDeploy {
    /// @notice Builds the CRE adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `setForwarder`/`setWorkflow`).
    /// @return cuts The facet cuts (ERC165 + AccessControl + ChainlinkCREAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ChainlinkCREAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new ChainlinkCREAdapter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new ChainlinkCREAdapterInit()), abi.encodeCall(ChainlinkCREAdapterInit.init, (admin))
        );
    }

    /// @notice Deploys a CRE adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The CRE adapter admin.
    /// @return cre The deployed CRE adapter diamond address.
    function run(address admin) external returns (address cre) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        cre = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
