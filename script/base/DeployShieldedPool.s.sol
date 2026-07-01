// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ShieldedPool} from "@lattice/privacy/ShieldedPool.sol";
import {ShieldedPoolInit} from "@lattice/privacy/ShieldedPoolInit.sol";

/// @title DeployShieldedPool
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a ShieldedPool diamond: `ERC165Facet` + `AccessControl` + `ShieldedPool` +
///         {ShieldedPoolInit}. The ONE source of truth for what a shielded-pool diamond is, shared by production
///         (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is part of the
///         base recipe because `createPool` is `DEFAULT_ADMIN_ROLE`-gated. Each pool's ERC-20 token and
///         `IShieldedWithdrawVerifier` are per-pool external dependencies (registered at `createPool`), not facets.
contract DeployShieldedPool is BaseDeploy {
    /// @notice Builds the ShieldedPool diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `createPool`).
    /// @return cuts The facet cuts (ERC165 + AccessControl + ShieldedPool).
    /// @return init The {ShieldedPoolInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new ShieldedPool()), "ShieldedPool");
        init = address(new ShieldedPoolInit());
        initCalldata = abi.encodeCall(ShieldedPoolInit.init, (admin));
    }

    /// @notice Deploys a ShieldedPool diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The pool admin (controls `createPool`).
    /// @return pool The deployed shielded-pool diamond address.
    function run(address admin) external returns (address pool) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        pool = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
