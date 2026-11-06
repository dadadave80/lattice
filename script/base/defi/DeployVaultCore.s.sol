// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {VaultCore} from "@lattice/defi/VaultCore.sol";
import {VaultCoreInit} from "@lattice/defi/VaultCoreInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC4626} from "@lattice/tokens/ERC4626/ERC4626.sol";

/// @title DeployVaultCore
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a VaultCore diamond — an ERC-4626 vault extended with strategy hooks:
///         `ERC165Facet` + `AccessControl` + `ERC20` + `ERC4626` + `VaultCore` + {VaultCoreInit}. Each facet owns
///         ONLY its own selectors (the composability principle): the base `ERC20` facet exposes the ERC-20 share
///         surface; `ERC4626` is a MIXED cut over it (REPLACE `decimals`, ADD the vault surface); and `VaultCore`
///         is a MIXED cut over `ERC4626` — it REPLACEs `totalAssets`/`deposit`/`mint`/`withdraw`/`redeem` (the
///         strategy-aware / rebalance-guarded variants) and `maxDeposit`/`maxMint` (deposit-latch-aware), and
///         ADDs the strategy-hook surface and the manager-swap latch (`IVaultCoreRecovery`). `AccessControl` is
///         cut so an admin can administer roles; strategy-manager changes are gated by `DEFAULT_ADMIN_ROLE`. The
///         ONE source of truth for what a VaultCore diamond is, shared by production and the facet tests.
contract DeployVaultCore is BaseDeploy {
    /// @notice Builds the VaultCore diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param asset_ The underlying ERC-20 asset the vault holds.
    /// @param name_ Vault share token name.
    /// @param symbol_ Vault share token symbol.
    /// @param admin_ The account granted `DEFAULT_ADMIN_ROLE`.
    /// @param decimalsOffset_ Virtual-share decimals offset for inflation-attack mitigation (usually 0).
    /// @return cuts The facet cuts (ERC165 + AccessControl + ERC20 + ERC4626 + VaultCore + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {VaultCoreInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(
        address asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        uint8 decimalsOffset_
    ) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _materialize(_cutPlan(0), _recipeSeams(0));

        (init, initCalldata) = _withUpgradeableIntrospection(
            _init("VaultCoreInit"),
            abi.encodeCall(VaultCoreInit.init, (asset_, name_, symbol_, admin_, decimalsOffset_))
        );
    }

    function _cutPlan(uint256 variant) internal pure returns (RecipeFacet[] memory cuts) {
        require(variant == 0, "DeployVaultCore: unknown variant");
        cuts = new RecipeFacet[](9);
        cuts[0] = RecipePlanLib.all("ERC165Facet");
        cuts[1] = RecipePlanLib.all("AccessControl");
        cuts[2] = RecipePlanLib.all("ERC20");
        cuts[3] = RecipePlanLib.only("ERC4626", FacetCutAction.Add, _vaultSurface());
        cuts[4] = RecipePlanLib.only("ERC4626", FacetCutAction.Replace, _decimals());
        cuts[5] = RecipePlanLib.only("VaultCore", FacetCutAction.Add, _strategySurface());
        cuts[6] = RecipePlanLib.only("VaultCore", FacetCutAction.Replace, _coreOverrides());
        cuts[7] = RecipePlanLib.all("DiamondLoupeFacet");
        cuts[8] = RecipePlanLib.all("AccessControlDiamondCut");
    }

    function _recipeSeams(uint256) internal pure returns (RecipeSeam[] memory seams) {
        seams = new RecipeSeam[](8);
        seams[0] = RecipePlanLib.seam2(
            "share-decimals",
            bytes4(keccak256("decimals()")),
            "ERC20",
            "ERC4626",
            "ERC4626",
            "share decimals include the virtual-share offset"
        );
        seams[1] = RecipePlanLib.seam2(
            "strategy.totalAssets()",
            bytes4(keccak256("totalAssets()")),
            "ERC4626",
            "VaultCore",
            "VaultCore",
            "strategy-aware accounting and manager-swap latch"
        );
        seams[2] = RecipePlanLib.seam2(
            "strategy.maxDeposit(address)",
            bytes4(keccak256("maxDeposit(address)")),
            "ERC4626",
            "VaultCore",
            "VaultCore",
            "strategy-aware accounting and manager-swap latch"
        );
        seams[3] = RecipePlanLib.seam2(
            "strategy.maxMint(address)",
            bytes4(keccak256("maxMint(address)")),
            "ERC4626",
            "VaultCore",
            "VaultCore",
            "strategy-aware accounting and manager-swap latch"
        );
        seams[4] = RecipePlanLib.seam2(
            "strategy.deposit(uint256,address)",
            bytes4(keccak256("deposit(uint256,address)")),
            "ERC4626",
            "VaultCore",
            "VaultCore",
            "strategy-aware accounting and manager-swap latch"
        );
        seams[5] = RecipePlanLib.seam2(
            "strategy.mint(uint256,address)",
            bytes4(keccak256("mint(uint256,address)")),
            "ERC4626",
            "VaultCore",
            "VaultCore",
            "strategy-aware accounting and manager-swap latch"
        );
        seams[6] = RecipePlanLib.seam2(
            "strategy.withdraw(uint256,address,address)",
            bytes4(keccak256("withdraw(uint256,address,address)")),
            "ERC4626",
            "VaultCore",
            "VaultCore",
            "strategy-aware accounting and manager-swap latch"
        );
        seams[7] = RecipePlanLib.seam2(
            "strategy.redeem(uint256,address,address)",
            bytes4(keccak256("redeem(uint256,address,address)")),
            "ERC4626",
            "VaultCore",
            "VaultCore",
            "strategy-aware accounting and manager-swap latch"
        );
    }

    function recipeSpec() public pure returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployVaultCore", "script/base/defi/DeployVaultCore.s.sol", 1);
        RecipeVariant memory variant;
        variant.id = "DeployVaultCore:buildCuts(address,string,string,address,uint8)";
        variant.buildSignature = "buildCuts(address,string,string,address,uint8)";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](5);
        variant.inputs[0] = RecipeParameter(
            "asset_",
            "address",
            "ERC20-contract",
            "target-configured-asset",
            "caller authenticates usable underlying; init permits zero and defaults decimals after failed reads"
        );
        variant.inputs[1] = RecipeParameter("name_", "string", "metadata", "Example Vault", "no length constraint");
        variant.inputs[2] = RecipeParameter("symbol_", "string", "metadata", "EVLT", "no length constraint");
        variant.inputs[3] = RecipeSpecLib.aclAdministrator("admin_");
        variant.inputs[4] = RecipeParameter(
            "decimalsOffset_",
            "uint8",
            "decimal-places",
            "0",
            "ABI uint8 only; caller chooses usable decimal and virtual-share arithmetic; no extra init clamp"
        );
        string[] memory bindings = new string[](5);
        for (uint256 i; i < bindings.length; ++i) {
            bindings[i] = variant.inputs[i].name;
        }
        variant.initPlan = RecipeSpecLib.introspected(
            RecipeSpecLib.leaf("VaultCoreInit", "init(address,string,string,address,uint8)", variant.inputs, bindings),
            true
        );
        variant.authorities = new RecipeAuthority[](1);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "admin_",
            "strategy-manager administration and diamondCut"
        );
        variant.conditions = new string[](1);
        variant.conditions[0] =
        "Manager replacement is a separate post-deployment configuration; no strategy is installed by init";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](1);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployVaultCore",
            "run(address,string,string,address,uint8)",
            variant,
            "buildCuts(asset_,name_,symbol_,admin_,decimalsOffset_)"
        );
    }

    /// @notice The ERC-4626 vault selectors that are NEW relative to the base ERC-20 facet (an `Add` cut).
    function _vaultSurface() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](16);
        s[0] = ERC4626.asset.selector;
        s[1] = ERC4626.totalAssets.selector;
        s[2] = ERC4626.convertToShares.selector;
        s[3] = ERC4626.convertToAssets.selector;
        s[4] = ERC4626.maxDeposit.selector;
        s[5] = ERC4626.maxMint.selector;
        s[6] = ERC4626.maxWithdraw.selector;
        s[7] = ERC4626.maxRedeem.selector;
        s[8] = ERC4626.previewDeposit.selector;
        s[9] = ERC4626.previewMint.selector;
        s[10] = ERC4626.previewWithdraw.selector;
        s[11] = ERC4626.previewRedeem.selector;
        s[12] = ERC4626.deposit.selector;
        s[13] = ERC4626.mint.selector;
        s[14] = ERC4626.withdraw.selector;
        s[15] = ERC4626.redeem.selector;
    }

    /// @notice The single `decimals()` selector the ERC-4626 facet REPLACEs on the base ERC-20 facet.
    function _decimals() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = ERC4626.decimals.selector;
    }

    /// @notice The strategy-hook and manager-swap-latch selectors VaultCore ADDs over ERC-4626.
    function _strategySurface() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](8);
        s[0] = VaultCore.strategyManager.selector;
        s[1] = VaultCore.idleAssets.selector;
        s[2] = VaultCore.allocatedAssets.selector;
        s[3] = VaultCore.setStrategyManager.selector;
        s[4] = VaultCore.allocateToStrategy.selector;
        s[5] = VaultCore.recallFromStrategy.selector;
        s[6] = VaultCore.managerSwapLatched.selector;
        s[7] = VaultCore.clearManagerSwapLatch.selector;
    }

    /// @notice The ERC-4626 selectors VaultCore REPLACEs (strategy-aware totalAssets, rebalance-guarded flows,
    ///         and the deposit-latch-aware `maxDeposit`/`maxMint`).
    function _coreOverrides() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](7);
        s[0] = VaultCore.totalAssets.selector;
        s[1] = VaultCore.deposit.selector;
        s[2] = VaultCore.mint.selector;
        s[3] = VaultCore.withdraw.selector;
        s[4] = VaultCore.redeem.selector;
        s[5] = VaultCore.maxDeposit.selector;
        s[6] = VaultCore.maxMint.selector;
    }

    /// @notice Deploys a VaultCore diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return vault The deployed vault diamond address.
    function run(address asset_, string memory name_, string memory symbol_, address admin_, uint8 decimalsOffset_)
        external
        returns (address vault)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(asset_, name_, symbol_, admin_, decimalsOffset_);
        vault = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
