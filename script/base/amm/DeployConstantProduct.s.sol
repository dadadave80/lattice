// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ConstantProduct} from "@lattice/amm/ConstantProduct.sol";
import {ConstantProductInit} from "@lattice/amm/ConstantProductInit.sol";

/// @title DeployConstantProduct
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a ConstantProduct AMM diamond: `ERC165Facet` + `AccessControl` +
///         `ConstantProduct` + {ConstantProductInit}. The ONE source of truth for what a constant-product pool
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on
///         {buildCuts}). `AccessControl` is part of the base recipe so pool administration is
///         `DEFAULT_ADMIN_ROLE`-gated; the pool is bound to its two ERC-20 reserve tokens at init.
contract DeployConstantProduct is BaseDeploy {
    /// @notice Builds the ConstantProduct pool diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param tokenA One of the two pool reserve tokens.
    /// @param tokenB The other pool reserve token.
    /// @return cuts The facet cuts (ERC165 + AccessControl + ConstantProduct).
    /// @return init The {ConstantProductInit} initializer address.
    /// @return initCalldata The `init(admin, tokenA, tokenB)` calldata.
    function buildCuts(address admin, address tokenA, address tokenB)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new ConstantProduct()));
        init = address(new ConstantProductInit());
        initCalldata = abi.encodeCall(ConstantProductInit.init, (admin, tokenA, tokenB));
    }

    /// @notice Deploys a ConstantProduct pool diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The pool admin.
    /// @param tokenA One of the two pool reserve tokens.
    /// @param tokenB The other pool reserve token.
    /// @return pool The deployed pool diamond address.
    function run(address admin, address tokenA, address tokenB) external returns (address pool) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, tokenA, tokenB);
        pool = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
