// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {GelatoVRFAdapter} from "@lattice/oracles/GelatoVRFAdapter.sol";
import {GelatoVRFAdapterInit} from "@lattice/oracles/GelatoVRFAdapterInit.sol";

/// @title DeployGelatoVRFAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Gelato VRF randomness diamond: `ERC165Facet` + `AccessControl` +
///         `GelatoVRFAdapter` + {GelatoVRFAdapterInit}. The ONE source of truth for what a Gelato VRF diamond is,
///         shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because the operator + request setters are admin-gated.
contract DeployGelatoVRFAdapter is BaseDeploy {
    /// @notice Builds the Gelato VRF diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the operator + request setters).
    /// @return cuts The facet cuts (ERC165 + AccessControl + GelatoVRFAdapter).
    /// @return init The {GelatoVRFAdapterInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new GelatoVRFAdapter()));
        init = address(new GelatoVRFAdapterInit());
        initCalldata = abi.encodeCall(GelatoVRFAdapterInit.init, (admin));
    }

    /// @notice Deploys a Gelato VRF diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The Gelato VRF admin.
    /// @return vrf The deployed Gelato VRF diamond address.
    function run(address admin) external returns (address vrf) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        vrf = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
