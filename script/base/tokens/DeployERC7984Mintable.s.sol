// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {TokenDeployBase} from "@lattice-script/base/tokens/TokenDeployBase.s.sol";
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
import {TokenRecipePlans} from "@lattice-script/lib/TokenRecipePlans.sol";
import {ERC7984MintableInit} from "@lattice/tokens/ERC7984/ERC7984MintableInit.sol";
import {ERC7984_MINTER_ROLE} from "@lattice/tokens/ERC7984/libraries/ERC7984MintableLib.sol";

/// @title DeployERC7984Mintable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a mintable ERC-7984 (confidential fungible token) diamond: the base
///         {DeployERC7984} cuts (`ERC165Facet` + `ERC7984` + `DiamondLoupeFacet`) with `AccessControl` +
///         `ERC7984Mintable` appended, sealed by a combined {ERC7984MintableInit}. The ONE source of truth for
///         what a mintable ERC-7984 diamond is, shared by production (`run --broadcast`) and the facet tests
///         (which build on {buildCuts}).
/// @dev Immutable by design: no cut facet is installed and no facet calls as the diamond, so neither the admin
///      nor a minter can run code as the diamond. Token operations need the Zama host contracts deployed on
///      that chain (1 and 11155111; 31337 is for local tests only).
contract DeployERC7984Mintable is TokenDeployBase {
    /// @notice Builds the mintable ERC-7984 diamond cuts + combined initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`, which administers `ERC7984_MINTER_ROLE`.
    /// @param minter The address granted `ERC7984_MINTER_ROLE`.
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @param contractURI_ Contract-level metadata URI.
    /// @return cuts The facet cuts (ERC165 + ERC7984 + DiamondLoupeFacet + AccessControl + ERC7984Mintable).
    /// @return init The {MultiInit} running {ERC7984MintableInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(
        address admin,
        address minter,
        string memory name_,
        string memory symbol_,
        string memory contractURI_
    ) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));
        (init, initCalldata) = _withImmutableIntrospection(
            _init("ERC7984MintableInit"),
            abi.encodeCall(ERC7984MintableInit.init, (admin, minter, name_, symbol_, contractURI_))
        );
    }

    /// @notice Deploys a mintable ERC-7984 token diamond (`forge script ... --broadcast`).
    /// @return token The deployed token diamond address.
    function run(address admin, address minter, string memory name_, string memory symbol_, string memory contractURI_)
        external
        returns (address token)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(admin, minter, name_, symbol_, contractURI_);
        token = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory) {
        require(variant == 0, "DeployERC7984Mintable: unknown variant");
        RecipeFacet[] memory extension = new RecipeFacet[](2);
        extension[0] = RecipePlanLib.all("AccessControl");
        extension[1] = RecipePlanLib.all("ERC7984Mintable");
        return RecipePlanLib.append(TokenRecipePlans.erc7984(false), extension);
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory) {
        return new RecipeSeam[](0);
    }

    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployERC7984Mintable", "script/base/tokens/DeployERC7984Mintable.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployERC7984Mintable:buildCuts(address,address,string,string,string)";
        variant.buildSignature = "buildCuts(address,address,string,string,string)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](5);
        variant.inputs[0] = RecipeSpecLib.aclAdministrator("admin");
        variant.inputs[1] = RecipeParameter(
            "minter",
            "address",
            "mint-authority",
            "0x00000000000000000000000000000000000000ae",
            "caller chooses the confidential mint authority; role grant permits zero"
        );
        variant.inputs[2] = RecipeParameter("name_", "string", "metadata", "Example Token", "no length constraint");
        variant.inputs[3] = RecipeParameter("symbol_", "string", "metadata", "EXM", "no length constraint");
        variant.inputs[4] =
            RecipeParameter("contractURI_", "string", "metadata", "ipfs://example", "no length constraint");
        string[] memory bindings = new string[](5);
        for (uint256 i; i < bindings.length; ++i) {
            bindings[i] = variant.inputs[i].name;
        }
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf(
                "ERC7984MintableInit", "init(address,address,string,string,string)", variant.inputs, bindings
            ),
            false
        );
        variant.authorities = new RecipeAuthority[](2);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin",
            "role administration only; no cut facet is installed"
        );
        variant.authorities[1] = RecipeSpecLib.role(
            "ERC7984Mintable",
            "ERC7984_MINTER_ROLE",
            "bytes32",
            ERC7984_MINTER_ROLE,
            "minter",
            "confidential mint; the minter learns each minted handle, zero on overflow, so each mint is a supply-threshold bit"
        );
        variant.conditions = new string[](3);
        variant.conditions[0] =
            "Only chains 1 and 11155111 (FHEVMLib.hostsFor); 31337 is for local tests only; others revert FHEVMUnsupportedChain";
        variant.conditions[1] =
            "Immutable by design: no cut facet and no diamond caller, so neither the admin nor a minter can run code as the diamond; a minter, or a self-granted admin, obtains ACL grants only on handles whose value it chose (its minted handles, supply handles its own consecutive mints produce, a never-credited recipient's first balance) and can publish those";
        variant.conditions[2] =
            "The admin can grant ERC7984_MINTER_ROLE to any account and is therefore a supply authority; each mint reveals whether the total supply exceeds 2^64-1 minus the amount, so minters and a self-granted admin can learn the supply in at most 64 mints; renouncing DEFAULT_ADMIN_ROLE freezes the minter set";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployERC7984Mintable",
            "run(address,address,string,string,string)",
            variant,
            "buildCuts(admin,minter,name_,symbol_,contractURI_)"
        );
    }
}
