// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {ERC4626} from "@lattice/tokens/ERC4626/ERC4626.sol";
import {ERC4626Init} from "@lattice/tokens/ERC4626/ERC4626Init.sol";

/// @title DeployERC4626
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-4626 tokenized-vault diamond: `ERC165Facet` + `ERC4626` +
///         {ERC4626Init}. The vault's shares ARE an ERC-20 token, and the `ERC4626` facet inherits the base
///         `ERC20` facet — so a SINGLE `ERC4626` cut exposes every ERC-20 share selector AND the vault
///         selectors over one shared storage layout (cutting a separate `ERC20` facet would duplicate the
///         `decimals()`/transfer/approve selectors and revert). The ONE source of truth for what a base vault
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on
///         {buildCuts}, appending test-only helper facets / a mintable underlying asset).
contract DeployERC4626 is BaseDeploy {
    /// @notice Builds the ERC-4626 vault diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param asset_ The underlying ERC-20 asset the vault holds.
    /// @param name_ Vault share token name.
    /// @param symbol_ Vault share token symbol.
    /// @param decimalsOffset_ Virtual-share decimals offset for inflation-attack mitigation (usually 0).
    /// @return cuts The facet cuts (ERC165 + ERC4626).
    /// @return init The {ERC4626Init} initializer address.
    /// @return initCalldata The `init(asset, name, symbol, offset)` calldata.
    function buildCuts(address asset_, string memory name_, string memory symbol_, uint8 decimalsOffset_)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](2);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new ERC4626()), "ERC4626");
        init = address(new ERC4626Init());
        initCalldata = abi.encodeCall(ERC4626Init.init, (asset_, name_, symbol_, decimalsOffset_));
    }

    /// @notice Deploys an ERC-4626 vault diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return vault The deployed vault diamond address.
    function run(address asset_, string memory name_, string memory symbol_, uint8 decimalsOffset_)
        external
        returns (address vault)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(asset_, name_, symbol_, decimalsOffset_);
        vault = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
