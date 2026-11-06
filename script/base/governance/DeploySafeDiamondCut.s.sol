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
import {SafeDiamondCut} from "@lattice/governance/SafeDiamondCut.sol";
import {SafeDiamondCutInit} from "@lattice/governance/SafeDiamondCutInit.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";

/// @title DeploySafeDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Safe-gated diamond-cut diamond: `ERC165Facet` + `DiamondLoupeFacet`
///         + `AccessControl` + `EmergencyStop` + `SafeDiamondCut` + {SafeDiamondCutInit}. The ONE source of
///         truth for what a Safe-gated cut diamond is, shared by production (`run --broadcast`) and the
///         facet tests (which build on {buildCuts}). The cut facet OWNS the canonical `diamondCut` selector
///         `0x1f931c1c`, gated by EmergencyStop + the pinned Safe; `AccessControl` + `EmergencyStop` are part
///         of the base recipe because the emergency + guardian surface is role-gated, and `DiamondLoupeFacet`
///         exposes `facetAddress` so tests can verify an applied cut.
contract DeploySafeDiamondCut is BaseDeploy {
    /// @notice Builds the Safe-gated cut diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (manages guardians and resumes operation).
    /// @param safe The Gnosis Safe multisig pinned as the sole cut authority.
    /// @param minThreshold The minimum signature threshold the pinned Safe must enforce.
    /// @return cuts The facet cuts (ERC165 + Loupe + AccessControl + EmergencyStop + SafeDiamondCut).
    /// @return init The {SafeDiamondCutInit} initializer address.
    /// @return initCalldata The `init(admin, safe, minThreshold)` calldata.
    function buildCuts(address admin, address safe, uint256 minThreshold)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(), new RecipeSeam[](0));
        init = _init("SafeDiamondCutInit");
        initCalldata = abi.encodeCall(SafeDiamondCutInit.init, (admin, safe, minThreshold));
    }

    function _cutPlan() internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](5);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[2] = RecipePlanLib.all("AccessControl");
        facets[3] = RecipePlanLib.all("EmergencyStop");
        facets[4] = RecipePlanLib.all("SafeDiamondCut");
    }

    /// @notice The Safe-gated topology, initializer arguments and role bootstrap as script data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeploySafeDiamondCut", "script/base/governance/DeploySafeDiamondCut.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeploySafeDiamondCut:buildCuts(address,address,uint256)";
        variant.buildSignature = "buildCuts(address,address,uint256)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan();
        variant.seams = new RecipeSeam[](0);
        variant.inputs = new RecipeParameter[](3);
        variant.inputs[0] = RecipeParameter(
            "admin",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable role administrator; initialization permits the zero address"
        );
        variant.inputs[1] = RecipeParameter(
            "safe",
            "address",
            "Safe-compatible-authority",
            "target-configured-safe",
            "enforced: nonzero and getThreshold() at least minThreshold; caller authenticates the Safe implementation"
        );
        variant.inputs[2] = RecipeParameter(
            "minThreshold",
            "uint256",
            "signature-count",
            "1",
            "enforced: greater than zero and no larger than Safe threshold"
        );
        string[] memory bindings = new string[](3);
        bindings[0] = "admin";
        bindings[1] = "safe";
        bindings[2] = "minThreshold";
        variant.initPlan =
            RecipeSpecLib.leaf("SafeDiamondCutInit", "init(address,address,uint256)", variant.inputs, bindings);
        variant.authorities = new RecipeAuthority[](2);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "guardian management and emergency resume"
        );
        variant.authorities[1] = RecipeSpecLib.externalAuthority(
            "SafeDiamondCut", "cutAuthority", "safe", "sole cut authority, with the configured minimum Safe threshold"
        );
        variant.conditions = new string[](1);
        variant.conditions[0] = "safe is the sole cut authority; DEFAULT_ADMIN_ROLE does not authorize diamondCut";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeploySafeDiamondCut", "run(address,address,uint256)", variant, "buildCuts(admin,safe,minThreshold)"
        );
    }

    /// @notice Deploys a Safe-gated cut diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The governance admin.
    /// @param safe The pinned Safe authority.
    /// @param minThreshold The minimum Safe signature threshold.
    /// @return safeDiamond The deployed Safe-gated cut diamond address.
    function run(address admin, address safe, uint256 minThreshold) external returns (address safeDiamond) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, safe, minThreshold);
        safeDiamond = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
