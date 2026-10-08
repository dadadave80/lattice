// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ENSSubnameIssuer} from "@lattice/ens/ENSSubnameIssuer.sol";
import {ENSSubnameIssuerInit} from "@lattice/ens/ENSSubnameIssuerInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployENSSubnameIssuer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ENS subname-issuer diamond: `ERC165Facet` + `AccessControl` +
///         `ENSSubnameIssuer` + {ENSSubnameIssuerInit}. The ONE source of truth for what an ENS subname-issuer
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because `issueSubname` and the wrapper setter are
///         `ENS_SUBNAME_ISSUER_ROLE`-gated; the external ENS NameWrapper is wired at init time.
contract DeployENSSubnameIssuer is BaseDeploy {
    /// @notice Builds the ENS subname-issuer diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls role assignment).
    /// @param wrapper The external ENS NameWrapper the facet forwards `setSubnodeRecord` to.
    /// @return cuts The facet cuts (ERC165 + AccessControl + ENSSubnameIssuer + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ENSSubnameIssuerInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address wrapper)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new ENSSubnameIssuer()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new ENSSubnameIssuerInit()), abi.encodeCall(ENSSubnameIssuerInit.init, (admin, wrapper))
        );
    }

    /// @notice Deploys an ENS subname-issuer diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The role admin.
    /// @param wrapper The external ENS NameWrapper.
    /// @return subnameIssuer The deployed ENS subname-issuer diamond address.
    function run(address admin, address wrapper) external returns (address subnameIssuer) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, wrapper);
        subnameIssuer = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
