// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ENSResolver} from "@lattice/ens/ENSResolver.sol";
import {ENSResolverInit} from "@lattice/ens/ENSResolverInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployENSResolver
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ENS forward-resolution diamond: `ERC165Facet` + `AccessControl` +
///         `ENSResolver` + {ENSResolverInit}. The ONE source of truth for what an ENS resolver diamond is, shared
///         by production (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is
///         part of the base recipe because the registry setter is `ENS_MANAGER_ROLE`-gated; the external ENS
///         registry the facet reads resolvers from is wired at init time.
contract DeployENSResolver is BaseDeploy {
    /// @notice Builds the ENS resolver diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls role assignment).
    /// @param registry The external ENS registry the facet reads resolvers from.
    /// @return cuts The facet cuts (ERC165 + AccessControl + ENSResolver + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ENSResolverInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address registry)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new ENSResolver()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new ENSResolverInit()), abi.encodeCall(ENSResolverInit.init, (admin, registry))
        );
    }

    /// @notice Deploys an ENS resolver diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The role admin.
    /// @param registry The external ENS registry.
    /// @return resolver The deployed ENS resolver diamond address.
    function run(address admin, address registry) external returns (address resolver) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, registry);
        resolver = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
