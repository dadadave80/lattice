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
    RecipeParameter,
    RecipeProxyKind,
    RecipeSeam,
    RecipeSpec,
    RecipeVariant
} from "@lattice-script/lib/RecipeSpec.sol";
import {RecipeSpecLib} from "@lattice-script/lib/RecipeSpecLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ENSResolverV2} from "@lattice/ens/ENSResolverV2.sol";
import {ENSResolverV2Init} from "@lattice/ens/ENSResolverV2Init.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployENSResolverV2
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Deploys an upgradeable diamond that reads ETH addresses from ENSv2.
contract DeployENSResolverV2 is BaseDeploy {
    /// @notice Builds the checked facet plan and initializes the resolver, administrator and introspection.
    function buildCuts(address admin, address universalResolver)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            _init("ENSResolverV2Init"), abi.encodeCall(ENSResolverV2Init.init, (universalResolver)), admin
        );
    }

    /// @notice Deploys the recipe atomically with the specified role administrator and authenticated proxy.
    function run(address admin, address universalResolver) external returns (address resolver) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory data) = buildCuts(admin, universalResolver);
        resolver = _assemble(cuts, init, data);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("ENSResolverV2");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Describes the same ordered cuts, initialization, parameters and authority as buildCuts.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployENSResolverV2", "script/base/ens/DeployENSResolverV2.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployENSResolverV2:buildCuts(address,address)";
        variant.buildSignature = "buildCuts(address,address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](2);
        variant.inputs[0] = RecipeSpecLib.aclAdministrator("admin");
        variant.inputs[1] = RecipeParameter(
            "universalResolver",
            "address",
            "ENSv2-universal-resolver",
            "target-configured-universal-resolver",
            "enforced: code and ENSv2 marker; caller authenticates the canonical proxy for the target chain"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](1);
        parameters[0] = variant.inputs[1];
        string[] memory bindings = new string[](1);
        bindings[0] = "universalResolver";
        variant.initPlan = RecipeSpecLib.adminIntrospected(
            RecipeSpecLib.leaf("ENSResolverV2Init", "init(address)", parameters, bindings), "admin"
        );
        variant.authorities = new RecipeAuthority[](2);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "role administration and diamondCut; grants ENS_MANAGER_ROLE to authorize proxy rotation"
        );
        variant.authorities[1] = RecipeSpecLib.externalAuthority(
            "ENSResolverV2",
            "universalResolver",
            "universalResolver",
            "the configured proxy supplies resolution answers"
        );
        variant.conditions = new string[](1);
        variant.conditions[0] =
            "caller: use a verified ENSv2 deployment on Ethereum or Sepolia; gateway records require direct client queries to the proxy";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployENSResolverV2", "run(address,address)", variant, "buildCuts(admin,universalResolver)"
        );
    }
}
