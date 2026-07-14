// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {CrosschainLinkInit} from "@lattice/crosschain/CrosschainLinkInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployCrosschainLink
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-7786 messaging diamond: `ERC165Facet` + `AccessControl` +
///         `CrosschainLink` + {CrosschainLinkInit}. The ONE source of truth for what a crosschain-link diamond
///         is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because every link/handler setter is
///         `DEFAULT_ADMIN_ROLE`-gated.
contract DeployCrosschainLink is BaseDeploy {
    /// @notice Builds the crosschain-link diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the link/handler registry).
    /// @return cuts The facet cuts (ERC165 + AccessControl + CrosschainLink + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {CrosschainLinkInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new CrosschainLink()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new CrosschainLinkInit()), abi.encodeCall(CrosschainLinkInit.init, (admin))
        );
    }

    /// @notice Deploys a crosschain-link diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The link/handler registry admin.
    /// @return link The deployed crosschain-link diamond address.
    function run(address admin) external returns (address link) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        link = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
