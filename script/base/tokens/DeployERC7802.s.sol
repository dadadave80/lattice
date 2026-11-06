// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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
import {TokenRecipePlans} from "@lattice-script/lib/TokenRecipePlans.sol";
import {CROSSCHAIN_BRIDGE_ROLE} from "@lattice/tokens/ERC7802/libraries/ERC7802Lib.sol";

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {TokenDeployBase} from "@lattice-script/base/tokens/TokenDeployBase.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC7802} from "@lattice/tokens/ERC7802/ERC7802.sol";
import {ERC7802Init} from "@lattice/tokens/ERC7802/ERC7802Init.sol";

/// @title DeployERC7802
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a crosschain-native ERC-20 (ERC-7802) diamond: the base {DeployERC20}
///         cuts (`ERC165Facet` + `ERC20`) with `AccessControl` + `ERC7802` appended, sealed by a combined
///         {ERC7802Init}. The ONE source of truth for what an ERC-7802 token diamond is, shared by production
///         (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is part of the
///         base recipe because `crosschainMint`/`crosschainBurn` are `CROSSCHAIN_BRIDGE_ROLE`-gated.
contract DeployERC7802 is TokenDeployBase {
    /// @notice Builds the ERC-7802 diamond cuts + combined initializer (no broadcast, no proxy deploy).
    /// @dev Reuses the shared base-token cuts, then appends `AccessControl` + `ERC7802`. The combined
    ///      {ERC7802Init} runs the full `__*_init` sequence in the single initializing window; no discarded
    ///      base initializer is deployed.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param bridge The trusted bridge granted `CROSSCHAIN_BRIDGE_ROLE`.
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @return cuts The facet cuts (ERC165 + ERC20 + DiamondLoupeFacet [base] + AccessControl + ERC7802 + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ERC7802Init} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address bridge, string memory name_, string memory symbol_)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));

        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("ERC7802Init"), abi.encodeCall(ERC7802Init.init, (admin, bridge, name_, symbol_))
        );
    }

    /// @notice Deploys an ERC-7802 crosschain-native token diamond (`forge script ... --broadcast`).
    /// @return token The deployed token diamond address.
    function run(address admin, address bridge, string memory name_, string memory symbol_)
        external
        returns (address token)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, bridge, name_, symbol_);
        token = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory cuts) {
        require(variant == 0, "DeployERC7802: unknown variant");
        RecipeFacet[] memory extension = new RecipeFacet[](3);
        extension[0] = RecipePlanLib.all("AccessControl");
        extension[1] = RecipePlanLib.all("ERC7802");
        extension[2] = RecipePlanLib.all("AccessControlDiamondCut");
        return RecipePlanLib.append(TokenRecipePlans.erc20(false), extension);
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC7802", "script/base/tokens/DeployERC7802.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployERC7802:buildCuts(address,address,string,string)";
        variant.buildSignature = "buildCuts(address,address,string,string)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](4);
        variant.inputs[0] = RecipeSpecLib.aclAdministrator("admin");
        variant.inputs[1] = RecipeParameter(
            "bridge",
            "address",
            "bridge-authority",
            "target-configured-bridge",
            "caller authenticates trusted mint/burn bridge; role grant permits zero"
        );
        variant.inputs[2] = RecipeParameter("name_", "string", "metadata", "Example Token", "no length constraint");
        variant.inputs[3] = RecipeParameter("symbol_", "string", "metadata", "EXM", "no length constraint");
        string[] memory bindings = new string[](4);
        for (uint256 i; i < bindings.length; ++i) {
            bindings[i] = variant.inputs[i].name;
        }
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("ERC7802Init", "init(address,address,string,string)", variant.inputs, bindings), true
        );
        variant.authorities = new RecipeAuthority[](2);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl", "DEFAULT_ADMIN_ROLE", "bytes32", bytes32(0), "admin", "role administration and diamondCut"
        );
        variant.authorities[1] = RecipeSpecLib.role(
            "ERC7802", "CROSSCHAIN_BRIDGE_ROLE", "bytes32", CROSSCHAIN_BRIDGE_ROLE, "bridge", "crosschain mint and burn"
        );
        variant.conditions = new string[](1);
        variant.conditions[0] =
        "The bridge is an explicit mint/burn authority; initialization does not authenticate its implementation";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployERC7802", "run(address,address,string,string)", variant, "buildCuts(admin,bridge,name_,symbol_)"
        );
    }
}
