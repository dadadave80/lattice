// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ChainlinkVRF} from "@lattice/oracles/ChainlinkVRF.sol";
import {ChainlinkVRFInit} from "@lattice/oracles/ChainlinkVRFInit.sol";

/// @title DeployChainlinkVRF
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Chainlink VRF randomness diamond: `ERC165Facet` + `AccessControl` +
///         `ChainlinkVRF` + {ChainlinkVRFInit}. The ONE source of truth for what a VRF diamond is, shared by
///         production (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is
///         part of the base recipe because every VRF config/request setter is `DEFAULT_ADMIN_ROLE`-gated.
contract DeployChainlinkVRF is BaseDeploy {
    /// @notice Builds the Chainlink VRF diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the VRF config + request setters).
    /// @return cuts The facet cuts (ERC165 + AccessControl + ChainlinkVRF).
    /// @return init The {ChainlinkVRFInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new ChainlinkVRF()), "ChainlinkVRF");
        init = address(new ChainlinkVRFInit());
        initCalldata = abi.encodeCall(ChainlinkVRFInit.init, (admin));
    }

    /// @notice Deploys a Chainlink VRF diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The VRF admin.
    /// @return vrf The deployed VRF diamond address.
    function run(address admin) external returns (address vrf) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        vrf = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
