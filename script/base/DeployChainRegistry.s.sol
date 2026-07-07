// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ChainRegistry} from "@lattice/crosschain/ChainRegistry.sol";
import {ChainRegistryInit} from "@lattice/crosschain/ChainRegistryInit.sol";

/// @title DeployChainRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a chain-registry diamond: `ERC165Facet` + `AccessControl` +
///         `ChainRegistry` + {ChainRegistryInit}. The ONE source of truth for what a chain-registry diamond
///         is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because every registry setter and the `addEvmChain`
///         fan-out are `DEFAULT_ADMIN_ROLE`-gated. The registry starts empty; chains are registered
///         post-deploy by the admin. In a production composition the gateway-adapter facets the fan-out
///         targets are cut into the SAME diamond alongside this recipe's cuts.
contract DeployChainRegistry is BaseDeploy {
    /// @notice Builds the chain-registry diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every setter and the fan-out).
    /// @return cuts The facet cuts (ERC165 + AccessControl + ChainRegistry).
    /// @return init The {ChainRegistryInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new ChainRegistry()), "ChainRegistry");
        init = address(new ChainRegistryInit());
        initCalldata = abi.encodeCall(ChainRegistryInit.init, (admin));
    }

    /// @notice Deploys a chain-registry diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The registry admin.
    /// @return registry The deployed chain-registry diamond address.
    function run(address admin) external returns (address registry) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        registry = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
