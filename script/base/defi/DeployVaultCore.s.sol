// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {VaultCore} from "@lattice/defi/VaultCore.sol";
import {VaultCoreInit} from "@lattice/defi/VaultCoreInit.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC4626} from "@lattice/tokens/ERC4626/ERC4626.sol";

/// @title DeployVaultCore
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a VaultCore diamond — an ERC-4626 vault extended with strategy hooks:
///         `ERC165Facet` + `AccessControl` + `ERC20` + `ERC4626` + `VaultCore` + {VaultCoreInit}. Each facet owns
///         ONLY its own selectors (the composability principle): the base `ERC20` facet exposes the ERC-20 share
///         surface; `ERC4626` is a MIXED cut over it (REPLACE `decimals`, ADD the vault surface); and `VaultCore`
///         is a MIXED cut over `ERC4626` — it REPLACEs `totalAssets`/`deposit`/`mint`/`withdraw`/`redeem` (the
///         strategy-aware / rebalance-guarded variants) and ADDs the strategy-hook surface. `AccessControl` is
///         cut so an admin can administer roles; strategy-manager changes are gated by `DEFAULT_ADMIN_ROLE`. The
///         ONE source of truth for what a VaultCore diamond is, shared by production and the facet tests.
contract DeployVaultCore is BaseDeploy {
    /// @notice Builds the VaultCore diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param asset_ The underlying ERC-20 asset the vault holds.
    /// @param name_ Vault share token name.
    /// @param symbol_ Vault share token symbol.
    /// @param admin_ The account granted `DEFAULT_ADMIN_ROLE`.
    /// @param decimalsOffset_ Virtual-share decimals offset for inflation-attack mitigation (usually 0).
    /// @return cuts The facet cuts (ERC165 + AccessControl + ERC20 + ERC4626 + VaultCore).
    /// @return init The {VaultCoreInit} initializer address.
    /// @return initCalldata The `init(asset, name, symbol, admin, offset)` calldata.
    function buildCuts(
        address asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        uint8 decimalsOffset_
    ) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        address vaultFacet = address(new ERC4626());
        address coreFacet = address(new VaultCore());

        cuts = new FacetCut[](7);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new ERC20()), "ERC20");
        // ERC-4626 vault surface over the ERC-20 shares: ADD the vault views/mutators, REPLACE `decimals`.
        cuts[3] = FacetCut({facetAddress: vaultFacet, action: FacetCutAction.Add, functionSelectors: _vaultSurface()});
        cuts[4] = FacetCut({facetAddress: vaultFacet, action: FacetCutAction.Replace, functionSelectors: _decimals()});
        // VaultCore over ERC-4626: ADD the strategy hooks, REPLACE the strategy-aware / guarded mutators.
        cuts[5] = FacetCut({facetAddress: coreFacet, action: FacetCutAction.Add, functionSelectors: _strategySurface()});
        cuts[6] =
            FacetCut({facetAddress: coreFacet, action: FacetCutAction.Replace, functionSelectors: _coreOverrides()});

        init = address(new VaultCoreInit());
        initCalldata = abi.encodeCall(VaultCoreInit.init, (asset_, name_, symbol_, admin_, decimalsOffset_));
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

    /// @notice The strategy-hook selectors VaultCore ADDs over ERC-4626.
    function _strategySurface() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](6);
        s[0] = VaultCore.strategyManager.selector;
        s[1] = VaultCore.idleAssets.selector;
        s[2] = VaultCore.allocatedAssets.selector;
        s[3] = VaultCore.setStrategyManager.selector;
        s[4] = VaultCore.allocateToStrategy.selector;
        s[5] = VaultCore.recallFromStrategy.selector;
    }

    /// @notice The ERC-4626 mutators VaultCore REPLACEs (strategy-aware totalAssets + rebalance-guarded flows).
    function _coreOverrides() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](5);
        s[0] = VaultCore.totalAssets.selector;
        s[1] = VaultCore.deposit.selector;
        s[2] = VaultCore.mint.selector;
        s[3] = VaultCore.withdraw.selector;
        s[4] = VaultCore.redeem.selector;
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
