// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {BridgeERC7802} from "@lattice/crosschain/BridgeERC7802.sol";
import {BridgeERC7802Init} from "@lattice/crosschain/BridgeERC7802Init.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";

/// @title DeployBridgeERC7802
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a mint/burn-bridge diamond over an ERC-7802 token: `ERC165Facet` +
///         `AccessControl` + `CrosschainLink` + `BridgeERC7802` + {BridgeERC7802Init}. The ONE source of truth
///         for what an ERC-7802 mint/burn bridge diamond is, shared by production (`run --broadcast`) and the
///         facet tests (which build on {buildCuts}). The bridge is registered as a handler on the co-mounted
///         `CrosschainLink` facet after deployment (an admin-gated `setHandler` call).
contract DeployBridgeERC7802 is BaseDeploy {
    /// @notice Builds the ERC-7802 mint/burn bridge diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the link/handler registry).
    /// @param token The ERC-7802 token minted/burned by the bridge.
    /// @return cuts The facet cuts (ERC165 + AccessControl + CrosschainLink + BridgeERC7802).
    /// @return init The {BridgeERC7802Init} initializer address.
    /// @return initCalldata The `init(admin, token)` calldata.
    function buildCuts(address admin, address token)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](4);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new CrosschainLink()), "CrosschainLink");
        cuts[3] = _cut(address(new BridgeERC7802()), "BridgeERC7802");
        init = address(new BridgeERC7802Init());
        initCalldata = abi.encodeCall(BridgeERC7802Init.init, (admin, token));
    }

    /// @notice Deploys an ERC-7802 mint/burn bridge diamond (broadcasting entrypoint for `forge script ...`).
    /// @param admin The link/handler registry admin.
    /// @param token The bridged ERC-7802 token.
    /// @return bridge The deployed bridge diamond address.
    function run(address admin, address token) external returns (address bridge) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, token);
        bridge = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
