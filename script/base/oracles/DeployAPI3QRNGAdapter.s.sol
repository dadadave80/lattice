// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {API3QRNGAdapter} from "@lattice/oracles/API3QRNGAdapter.sol";
import {API3QRNGAdapterInit} from "@lattice/oracles/API3QRNGAdapterInit.sol";

/// @title DeployAPI3QRNGAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an API3 QRNG randomness diamond: `ERC165Facet` + `AccessControl` +
///         `API3QRNGAdapter` + {API3QRNGAdapterInit}. The ONE source of truth for what a QRNG diamond is, shared
///         by production (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl`
///         is part of the base recipe because every QRNG config/request setter is `DEFAULT_ADMIN_ROLE`-gated.
contract DeployAPI3QRNGAdapter is BaseDeploy {
    /// @notice Builds the API3 QRNG diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the QRNG config + request setters).
    /// @return cuts The facet cuts (ERC165 + AccessControl + API3QRNGAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {API3QRNGAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new API3QRNGAdapter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new API3QRNGAdapterInit()), abi.encodeCall(API3QRNGAdapterInit.init, (admin))
        );
    }

    /// @notice Deploys an API3 QRNG diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The QRNG admin.
    /// @return qrng The deployed QRNG diamond address.
    function run(address admin) external returns (address qrng) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        qrng = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
