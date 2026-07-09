// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {TWAPOracle} from "@lattice/oracles/TWAPOracle.sol";
import {TWAPOracleInit} from "@lattice/oracles/TWAPOracleInit.sol";

/// @title DeployTWAPOracle
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a TWAPOracle diamond: `ERC165Facet` + `AccessControl` + `TWAPOracle` +
///         {TWAPOracleInit}. The ONE source of truth for what a TWAP oracle diamond is, shared by production
///         (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is part of the
///         base recipe because pair registration/unregistration is `DEFAULT_ADMIN_ROLE`-gated (observation
///         recording is permissionless).
contract DeployTWAPOracle is BaseDeploy {
    /// @notice Builds the TWAPOracle diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessControl + TWAPOracle).
    /// @return init The {TWAPOracleInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new TWAPOracle()));
        init = address(new TWAPOracleInit());
        initCalldata = abi.encodeCall(TWAPOracleInit.init, (admin));
    }

    /// @notice Deploys a TWAPOracle diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The oracle admin.
    /// @return oracle The deployed TWAP oracle diamond address.
    function run(address admin) external returns (address oracle) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        oracle = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
