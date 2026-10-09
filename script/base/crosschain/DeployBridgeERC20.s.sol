// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {BridgeERC20} from "@lattice/crosschain/BridgeERC20.sol";
import {BridgeERC20Init} from "@lattice/crosschain/BridgeERC20Init.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployBridgeERC20
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a custody-bridge diamond over a legacy ERC-20: `ERC165Facet` +
///         `AccessControl` + `CrosschainLink` + `BridgeERC20` + {BridgeERC20Init}. The ONE source of truth for
///         what an ERC-20 custody bridge diamond is, shared by production (`run --broadcast`) and the facet tests
///         (which build on {buildCuts}). The bridge is registered as a handler on the co-mounted `CrosschainLink`
///         facet after deployment (an admin-gated `setHandler` call).
contract DeployBridgeERC20 is BaseDeploy {
    /// @notice Builds the ERC-20 custody bridge diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the link/handler registry).
    /// @param token The legacy ERC-20 token custodied by the bridge.
    /// @return cuts The facet cuts (ERC165 + AccessControl + CrosschainLink + BridgeERC20 + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {BridgeERC20Init} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address token)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new CrosschainLink()));
        cuts[3] = _cut(address(new BridgeERC20()));
        cuts[4] = _cut(address(new DiamondLoupeFacet()));
        cuts[5] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new BridgeERC20Init()), abi.encodeCall(BridgeERC20Init.init, (admin, token))
        );
    }

    /// @notice Deploys an ERC-20 custody bridge diamond (broadcasting entrypoint for `forge script ...`).
    /// @param admin The link/handler registry admin.
    /// @param token The bridged ERC-20 token.
    /// @return bridge The deployed bridge diamond address.
    function run(address admin, address token) external returns (address bridge) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, token);
        bridge = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
