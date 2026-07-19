// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployAccessControl
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for the foundation role diamond: `ERC165Facet` + `AccessControl` +
///         {AccessControlInit}. The ONE source of truth for what an AccessControl diamond is, shared by
///         production (`run --broadcast`) and the facet tests (which build on {buildCuts}). `admin` receives the
///         `DEFAULT_ADMIN_ROLE` that gates every grant/revoke.
contract DeployAccessControl is BaseDeploy {
    /// @notice Builds the AccessControl diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessControl + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {AccessControlInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new DiamondLoupeFacet()));
        cuts[3] = _cut(address(new AccessControlDiamondCut()));
        cuts[4] = _cut(address(new Receive()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new AccessControlInit()), abi.encodeCall(AccessControlInit.init, (admin))
        );
    }

    /// @notice Deploys an AccessControl diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The role admin.
    /// @return accessControl The deployed AccessControl diamond address.
    function run(address admin) external returns (address accessControl) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        accessControl = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
