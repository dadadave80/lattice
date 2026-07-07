// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ENSReverseClaimer} from "@lattice/ens/ENSReverseClaimer.sol";
import {ENSReverseClaimerInit} from "@lattice/ens/ENSReverseClaimerInit.sol";

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
    /// @return cuts The facet cuts (ERC165 + AccessControl + ENSReverseClaimer).
    /// @return init The {ENSReverseClaimerInit} initializer address.
    /// @return initCalldata The `init(admin, registrar)` calldata.
    function buildCuts(address admin, address registrar)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new ENSReverseClaimer()), "ENSReverseClaimer");
        init = address(new ENSReverseClaimerInit());
        initCalldata = abi.encodeCall(ENSReverseClaimerInit.init, (admin, registrar));
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
