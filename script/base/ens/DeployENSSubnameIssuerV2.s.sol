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
import {ENSSubnameIssuerV2} from "@lattice/ens/ENSSubnameIssuerV2.sol";
import {ENSSubnameIssuerV2Init} from "@lattice/ens/ENSSubnameIssuerV2Init.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployENSSubnameIssuerV2
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Atomically deploys an upgradeable diamond for issuing subnames under canonical ENSv2 parents.
contract DeployENSSubnameIssuerV2 is BaseDeploy {
    /// @notice Builds the issuer's cuts and multi-init calldata without deploying the diamond.
    /// @param admin The default administrator for the diamond's AccessControl.
    /// @param helper The verified Universal Helper on the target chain.
    /// @return cuts The issuer, role management, cut, and introspection facets.
    /// @return init The MultiInit target that runs the module, admin, and introspection steps.
    /// @return initCalldata The matching multiInit calldata.
    function buildCuts(address admin, address helper)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(), new RecipeSeam[](0));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            _init("ENSSubnameIssuerV2Init"), abi.encodeCall(ENSSubnameIssuerV2Init.init, (helper)), admin
        );
    }

    /// @notice Broadcasts an atomic issuer diamond deployment through the factory.
    /// @param admin The default administrator for the diamond's AccessControl.
    /// @param helper The verified Universal Helper on the target chain.
    /// @return subnameIssuer The deployed diamond.
    function run(address admin, address helper) external returns (address subnameIssuer) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, helper);
        subnameIssuer = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan() internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("ENSSubnameIssuerV2");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    /// @notice Canonical cut plan, initializer steps and deployment inputs.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployENSSubnameIssuerV2", "script/base/ens/DeployENSSubnameIssuerV2.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployENSSubnameIssuerV2:buildCuts(address,address)";
        variant.buildSignature = "buildCuts(address,address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan();
        variant.seams = new RecipeSeam[](0);
        variant.inputs = new RecipeParameter[](2);
        variant.inputs[0] = RecipeParameter(
            "admin",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable role and upgrade administrator; initialization permits the zero address"
        );
        variant.inputs[1] = RecipeParameter(
            "helper",
            "address",
            "ENSv2-UniversalHelper",
            "target-configured-universal-helper",
            "enforced: code on helper and its reported root; caller authenticates the published deployment"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](1);
        parameters[0] = variant.inputs[1];
        string[] memory bindings = new string[](1);
        bindings[0] = "helper";
        variant.initPlan = RecipeSpecLib.adminIntrospected(
            RecipeSpecLib.leaf("ENSSubnameIssuerV2Init", "init(address)", parameters, bindings), "admin"
        );
        variant.authorities = new RecipeAuthority[](2);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "role administration and diamondCut; grants ENS_MANAGER_ROLE to authorize helper rotation"
        );
        variant.authorities[1] = RecipeSpecLib.externalAuthority(
            "ENSSubnameIssuerV2", "ensUniversalHelper", "helper", "selects the canonical registry for each parent name"
        );
        variant.conditions = new string[](3);
        variant.conditions[0] = "caller: configure the official ENSv2 helper on an ENS deployment network";
        variant.conditions[1] =
        "parent registry owner: grant the diamond ROLE_REGISTRAR on that registry's root resource";
        variant.conditions[2] = "admin: grant ENS_V2_SUBNAME_ISSUER_ROLE to trusted operators before issuance";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployENSSubnameIssuerV2", "run(address,address)", variant, "buildCuts(admin,helper)"
        );
    }
}
