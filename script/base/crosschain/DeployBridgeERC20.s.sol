// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {RecipePlanLib} from "@lattice-script/lib/RecipePlanLib.sol";
import {
    RecipeAuthority,
    RecipeDeploymentContext,
    RecipeFacet,
    RecipeInitOutputKind,
    RecipeInitStep,
    RecipeParameter,
    RecipeProxyKind,
    RecipeSeam,
    RecipeSpec,
    RecipeVariant
} from "@lattice-script/lib/RecipeSpec.sol";
import {RecipeSpecLib} from "@lattice-script/lib/RecipeSpecLib.sol";
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
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("BridgeERC20Init"), abi.encodeCall(BridgeERC20Init.init, (admin, token))
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

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployBridgeERC20: unknown variant");
        facets = new RecipeFacet[](6);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("CrosschainLink");
        facets[3] = RecipePlanLib.all("BridgeERC20");
        facets[4] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[5] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical builder variants and exact ordered initializer calls as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployBridgeERC20", "script/base/crosschain/DeployBridgeERC20.s.sol", 1);
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        RecipeVariant memory variant;
        variant.id = "DeployBridgeERC20:buildCuts(address,address)";
        variant.buildSignature = "buildCuts(address,address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](2);
        variant.inputs[0] = RecipeParameter(
            "admin",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
        );
        variant.inputs[1] = RecipeParameter(
            "token",
            "address",
            "ERC20-custody-token",
            "mock-or-target-configured-ERC20",
            "enforced: nonzero; caller authenticates the ERC20 token and its transfer behavior"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](2);
        parameters[0] = variant.inputs[0];
        parameters[1] = variant.inputs[1];
        string[] memory bindings = new string[](2);
        bindings[0] = "admin";
        bindings[1] = "token";
        RecipeInitStep[] memory module =
            RecipeSpecLib.leaf("BridgeERC20Init", "init(address,address)", parameters, bindings);
        variant.initPlan = RecipeSpecLib.introspected(module, true);
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "module configuration, role administration and diamondCut"
        );
        variant.conditions = new string[](1);
        variant.conditions[0] =
            "caller: configure CrosschainLink gateways and counterparts, and register this bridge as a handler after deployment";
        result.variants[0] = variant;
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployBridgeERC20", "run(address,address)", variant, "buildCuts(admin,token)"
        );
    }
}
