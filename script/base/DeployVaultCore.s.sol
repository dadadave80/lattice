// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {VaultCore} from "@lattice/defi/VaultCore.sol";
import {VaultCoreInit} from "@lattice/defi/VaultCoreInit.sol";

/// @title DeployVaultCore
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a VaultCore diamond — an ERC-4626 vault extended with strategy hooks:
///         `ERC165Facet` + `AccessControl` + `VaultCore` + {VaultCoreInit}. `VaultCore` inherits `ERC4626`
///         (which inherits the base `ERC20`), so a SINGLE `VaultCore` cut exposes every ERC-20 share selector,
///         the ERC-4626 vault selectors (with the VaultCore overrides of `totalAssets`/deposit/mint/withdraw/
///         redeem), AND the strategy-hook selectors over one shared storage layout. `AccessControl` is cut in
///         so an admin can administer roles; strategy-manager changes are gated by `DEFAULT_ADMIN_ROLE`. The
///         ONE source of truth for what a VaultCore diamond is, shared by production and the facet tests.
contract DeployVaultCore is BaseDeploy {
    /// @notice Builds the VaultCore diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param asset_ The underlying ERC-20 asset the vault holds.
    /// @param name_ Vault share token name.
    /// @param symbol_ Vault share token symbol.
    /// @param admin_ The account granted `DEFAULT_ADMIN_ROLE`.
    /// @param decimalsOffset_ Virtual-share decimals offset for inflation-attack mitigation (usually 0).
    /// @return cuts The facet cuts (ERC165 + AccessControl + VaultCore).
    /// @return init The {VaultCoreInit} initializer address.
    /// @return initCalldata The `init(asset, name, symbol, admin, offset)` calldata.
    function buildCuts(
        address asset_,
        string memory name_,
        string memory symbol_,
        address admin_,
        uint8 decimalsOffset_
    ) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new VaultCore()), "VaultCore");
        init = address(new VaultCoreInit());
        initCalldata = abi.encodeCall(VaultCoreInit.init, (asset_, name_, symbol_, admin_, decimalsOffset_));
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
