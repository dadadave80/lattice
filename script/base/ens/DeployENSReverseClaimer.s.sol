// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ENSReverseClaimer} from "@lattice/ens/ENSReverseClaimer.sol";
import {ENSReverseClaimerInit} from "@lattice/ens/ENSReverseClaimerInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployENSReverseClaimer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ENS reverse-claim diamond: `ERC165Facet` + `AccessControl` +
///         `ENSReverseClaimer` + {ENSReverseClaimerInit}. The ONE source of truth for what an ENS reverse-claimer
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because `setEnsName` and the registrar setter are
///         `ENS_MANAGER_ROLE`-gated; the external ENS reverse registrar is wired at init time.
contract DeployENSReverseClaimer is BaseDeploy {
    /// @notice Builds the ENS reverse-claimer diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls role assignment).
    /// @param registrar The external ENS reverse registrar the facet forwards `setName` to.
    /// @return cuts The facet cuts (ERC165 + AccessControl + ENSReverseClaimer + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ENSReverseClaimerInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address registrar)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new ENSReverseClaimer()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        cuts[5] = _cut(address(new Receive()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new ENSReverseClaimerInit()), abi.encodeCall(ENSReverseClaimerInit.init, (admin, registrar))
        );
    }

    /// @notice Deploys an ENS reverse-claimer diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The role admin.
    /// @param registrar The external ENS reverse registrar.
    /// @return claimer The deployed ENS reverse-claimer diamond address.
    function run(address admin, address registrar) external returns (address claimer) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, registrar);
        claimer = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
