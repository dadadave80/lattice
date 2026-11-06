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
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {HTSAdapter} from "@lattice/tokens/hedera/HTSAdapter.sol";
import {HTSAdapterInit} from "@lattice/tokens/hedera/HTSAdapterInit.sol";
import {HTS_MANAGER_ROLE, HTS_OPERATOR_ROLE} from "@lattice/tokens/hedera/HTSAdapterLib.sol";

/// @title DeployHTSAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Hedera Token Service diamond: `ERC165Facet` + `AccessControl` +
///         `HTSAdapter` + {HTSAdapterInit}. The ONE source of truth for what an HTS diamond is, shared by
///         production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because every association, creation and treasury
///         mutator is role-gated (`HTS_MANAGER_ROLE` / `HTS_OPERATOR_ROLE`). `Receive` is part of it because
///         the diamond is the treasury AND the auto-renew account of every token it creates, so it must be
///         able to hold HBAR — a plain transfer is how it gets funded for the auto-renewal the network
///         charges it and for the creation fees it forwards as `msg.value`.
contract DeployHTSAdapter is BaseDeploy {
    /// @notice Builds the HTS diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`, `HTS_MANAGER_ROLE` and `HTS_OPERATOR_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessControl + HTSAdapter + DiamondLoupeFacet +
    ///         AccessControlDiamondCut + Receive).
    /// @return init The {MultiInit} running {HTSAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) =
            _withUpgradeableIntrospection(_init("HTSAdapterInit"), abi.encodeCall(HTSAdapterInit.init, (admin)));
    }

    function _cutPlan(uint256) internal pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](6);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("HTSAdapter");
        facets[3] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
        facets[5] = RecipePlanLib.all("Receive");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    /// @notice The native HTS dependency, exact role grants and shared cut/init plan as script-only data.
    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployHTSAdapter", "script/base/tokens/DeployHTSAdapter.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployHTSAdapter:buildCuts(address)";
        variant.buildSignature = "buildCuts(address)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](1);
        variant.inputs[0] = RecipeParameter(
            "admin",
            "address",
            "account",
            "0x00000000000000000000000000000000000000ad",
            "caller: choose a usable role administrator, HTS manager/operator and upgrade authority; initialization permits the zero address"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](1);
        parameters[0] = RecipeParameter(
            "admin", "address", variant.inputs[0].unit, variant.inputs[0].example, variant.inputs[0].rule
        );
        string[] memory bindings = new string[](1);
        bindings[0] = "admin";
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("HTSAdapterInit", "init(address)", parameters, bindings), true
        );
        variant.authorities = new RecipeAuthority[](3);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl", "DEFAULT_ADMIN_ROLE", "bytes32", bytes32(0), "admin", "role administration and diamondCut"
        );
        variant.authorities[1] = RecipeSpecLib.role(
            "HTSAdapter",
            "HTS_MANAGER_ROLE",
            "bytes32",
            HTS_MANAGER_ROLE,
            "admin",
            "associate/dissociate the diamond and create tokens treasuried by it"
        );
        variant.authorities[2] = RecipeSpecLib.role(
            "HTSAdapter",
            "HTS_OPERATOR_ROLE",
            "bytes32",
            HTS_OPERATOR_ROLE,
            "admin",
            "transfer the diamond's balances, spend its granted allowances and mint/burn through HTS"
        );
        variant.conditions = new string[](4);
        variant.conditions[0] =
            "the bundle initializes AccessControl, grants both HTS roles to admin, and registers HTSAdapter; token associations and creation occur later";
        variant.conditions[1] =
            "caller: use a target network providing the compatible Hedera HTS system contract at 0x0000000000000000000000000000000000000167; this native address has no bytecode, and initialization performs no HTS availability check";
        variant.conditions[2] =
            "caller: fund the diamond with HBAR through Receive for forwarded creation fees and native auto-renew charges; initialization does not fund it";
        variant.conditions[3] =
            "HTS validates the diamond's associations, balances, allowances and token keys; the library calls it normally from the diamond and assigns delegatableContractId diamond keys to created tokens";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] =
            RecipeSpecLib.deploymentContext("DeployHTSAdapter", "run(address)", variant, "buildCuts(admin)");
    }

    /// @notice Deploys an HTS diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The HTS manager / operator admin.
    /// @return hts The deployed HTS diamond address.
    function run(address admin) external returns (address hts) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        hts = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
