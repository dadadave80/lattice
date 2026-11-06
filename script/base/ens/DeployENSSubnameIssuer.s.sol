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
import {ENSSubnameIssuer} from "@lattice/ens/ENSSubnameIssuer.sol";
import {ENSSubnameIssuerInit} from "@lattice/ens/ENSSubnameIssuerInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployENSSubnameIssuer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ENS subname-issuer diamond: `ERC165Facet` + `AccessControl` +
///         `ENSSubnameIssuer` + {ENSSubnameIssuerInit}. The ONE source of truth for what an ENS subname-issuer
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because `issueSubname` and the wrapper setter are
///         `ENS_SUBNAME_ISSUER_ROLE`-gated; the external ENS NameWrapper is wired at init time.
contract DeployENSSubnameIssuer is BaseDeploy {
    /// @notice Builds the ENS subname-issuer diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls role assignment).
    /// @param wrapper The external ENS NameWrapper the facet forwards `setSubnodeRecord` to.
    /// @return cuts The facet cuts (ERC165 + AccessControl + ENSSubnameIssuer + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ENSSubnameIssuerInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address wrapper)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("ENSSubnameIssuerInit"), abi.encodeCall(ENSSubnameIssuerInit.init, (admin, wrapper))
        );
    }

    /// @notice Deploys an ENS subname-issuer diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The role admin.
    /// @param wrapper The external ENS NameWrapper.
    /// @return subnameIssuer The deployed ENS subname-issuer diamond address.
    function run(address admin, address wrapper) external returns (address subnameIssuer) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, wrapper);
        subnameIssuer = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployENSSubnameIssuer: unknown variant");
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("ENSSubnameIssuer");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice Canonical cut plan, typed initializer tree and deployment inputs as script-only recipe data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployENSSubnameIssuer", "script/base/ens/DeployENSSubnameIssuer.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployENSSubnameIssuer:buildCuts(address,address)";
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
            "wrapper",
            "address",
            "ENS-NameWrapper",
            "target-configured-name-wrapper",
            "enforced: nonzero; caller authenticates the NameWrapper and arranges parent-name control for this diamond"
        );
        string[] memory bindings = new string[](2);
        bindings[0] = "admin";
        bindings[1] = "wrapper";
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("ENSSubnameIssuerInit", "init(address,address)", variant.inputs, bindings), true
        );
        variant.authorities = new RecipeAuthority[](2);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "role administration and diamondCut; ENS_SUBNAME_ISSUER_ROLE requires a separate grant"
        );
        variant.authorities[1] = RecipeSpecLib.externalAuthority(
            "ENSSubnameIssuer",
            "nameWrapper",
            "wrapper",
            "the configured wrapper enforces wrapped parent-name ownership and records issued subnames"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
            "initialization grants DEFAULT_ADMIN_ROLE only; caller must grant ENS_SUBNAME_ISSUER_ROLE before issuance or wrapper changes";
        variant.conditions[1] =
        "caller: arrange the NameWrapper parent ownership or approval needed for this diamond to issue subnames";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployENSSubnameIssuer", "run(address,address)", variant, "buildCuts(admin,wrapper)"
        );
    }
}
