// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {StrategyManager} from "@lattice/defi/StrategyManager.sol";
import {StrategyManagerInit} from "@lattice/defi/StrategyManagerInit.sol";

/// @title DeployStrategyManager
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a StrategyManager diamond: `ERC165Facet` + `AccessControl` +
///         `StrategyManager` + {StrategyManagerInit}. The ONE source of truth for what a strategy-manager
///         diamond is, shared by production (`run --broadcast`) and the facet tests (which build on
///         {buildCuts}). `AccessControl` is part of the base recipe because every vault/strategy setter is
///         `DEFAULT_ADMIN_ROLE`-gated.
contract DeployStrategyManager is BaseDeploy {
    /// @notice Builds the StrategyManager diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessControl + StrategyManager).
    /// @return init The {StrategyManagerInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new StrategyManager()), "StrategyManager");
        init = address(new StrategyManagerInit());
        initCalldata = abi.encodeCall(StrategyManagerInit.init, (admin));
    }

    /// @notice Deploys a StrategyManager diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The strategy-manager admin.
    /// @return manager The deployed strategy-manager diamond address.
    function run(address admin) external returns (address manager) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        manager = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
