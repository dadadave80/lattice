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

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {TokenDeployBase} from "@lattice-script/base/tokens/TokenDeployBase.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC20Crosschain} from "@lattice/tokens/ERC20/ERC20Crosschain.sol";
import {ERC20CrosschainInit} from "@lattice/tokens/ERC20/ERC20CrosschainInit.sol";

/// @title DeployERC20Crosschain
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a self-bridging ERC-20 diamond: the base {DeployERC20} cuts
///         (`ERC165Facet` + `ERC20`) with `AccessControl` + `CrosschainLink` + `ERC20Crosschain` appended,
///         sealed by a combined {ERC20CrosschainInit}. The ONE source of truth for what a self-bridging ERC-20
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because the crosschain-link setters are admin-gated.
contract DeployERC20Crosschain is TokenDeployBase {
    /// @notice Builds the self-bridging ERC-20 diamond cuts + combined initializer (no broadcast, no deploy).
    /// @dev Reuses the shared base-token cuts, then appends `AccessControl` + `CrosschainLink` +
    ///      `ERC20Crosschain`. The combined {ERC20CrosschainInit} runs the full `__*_init` sequence in the
    ///      single initializing window; no discarded base initializer is deployed.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @return cuts The facet cuts (ERC165 + ERC20 + DiamondLoupeFacet [base] + AccessControl + CrosschainLink + ERC20Crosschain + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ERC20CrosschainInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, string memory name_, string memory symbol_)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));

        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("ERC20CrosschainInit"), abi.encodeCall(ERC20CrosschainInit.init, (admin, name_, symbol_))
        );
    }

    /// @notice Deploys a self-bridging ERC-20 token diamond (`forge script ... --broadcast`).
    /// @return token The deployed token diamond address.
    function run(address admin, string memory name_, string memory symbol_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, name_, symbol_);
        token = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory cuts) {
        require(variant == 0, "DeployERC20Crosschain: unknown variant");
        RecipeFacet[] memory extension = new RecipeFacet[](4);
        extension[0] = RecipePlanLib.all("AccessControl");
        extension[1] = RecipePlanLib.all("CrosschainLink");
        extension[2] = RecipePlanLib.all("ERC20Crosschain");
        extension[3] = RecipePlanLib.all("AccessControlDiamondCut");
        return RecipePlanLib.append(TokenRecipePlans.erc20(false), extension);
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC20Crosschain", "script/base/tokens/DeployERC20Crosschain.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployERC20Crosschain:buildCuts(address,string,string)";
        variant.buildSignature = "buildCuts(address,string,string)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](3);
        variant.inputs[0] = RecipeSpecLib.aclAdministrator("admin");
        variant.inputs[1] = RecipeParameter("name_", "string", "metadata", "Example Token", "no length constraint");
        variant.inputs[2] = RecipeParameter("symbol_", "string", "metadata", "EXM", "no length constraint");
        string[] memory bindings = new string[](3);
        for (uint256 i; i < bindings.length; ++i) {
            bindings[i] = variant.inputs[i].name;
        }
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("ERC20CrosschainInit", "init(address,string,string)", variant.inputs, bindings), true
        );
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "crosschain links, handler registry and diamondCut"
        );
        variant.conditions = new string[](2);
        variant.conditions[0] =
            "Links, gateways and receive handlers require separate admin configuration; init creates no trusted remote routes";
        variant.conditions[1] =
        "ERC20Crosschain receive path requires a diamond self-call dispatched by the configured crosschain handler";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployERC20Crosschain", "run(address,string,string)", variant, "buildCuts(admin,name_,symbol_)"
        );
    }
}
