// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ERC7786OpenBridge} from "@lattice/crosschain/ERC7786OpenBridge.sol";
import {ERC7786OpenBridgeInit} from "@lattice/crosschain/ERC7786OpenBridgeInit.sol";

/// @title DeployERC7786OpenBridge
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-7786 open-bridge diamond: `ERC165Facet` + `AccessControl` +
///         `ERC7786OpenBridge` + {ERC7786OpenBridgeInit}. The ONE source of truth for what an open-bridge diamond
///         is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because the gateway-set, threshold and remote-bridge setters
///         are `DEFAULT_ADMIN_ROLE`-gated. The bridge is gateway-agnostic, so the gateway set is configured
///         post-deploy by the admin rather than at init.
contract DeployERC7786OpenBridge is BaseDeploy {
    /// @notice Builds the open-bridge diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the gateway set, threshold and remotes).
    /// @return cuts The facet cuts (ERC165 + AccessControl + ERC7786OpenBridge).
    /// @return init The {ERC7786OpenBridgeInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new ERC7786OpenBridge()));
        init = address(new ERC7786OpenBridgeInit());
        initCalldata = abi.encodeCall(ERC7786OpenBridgeInit.init, (admin));
    }

    /// @notice Deploys an open-bridge diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The bridge admin.
    /// @return bridge The deployed open-bridge diamond address.
    function run(address admin) external returns (address bridge) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        bridge = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
