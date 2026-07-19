// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {TWAPOracle} from "@lattice/oracles/uniswap/TWAPOracle.sol";
import {TWAPOracleInit} from "@lattice/oracles/uniswap/TWAPOracleInit.sol";

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
    /// @return cuts The facet cuts (ERC165 + AccessControl + TWAPOracle + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {TWAPOracleInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new TWAPOracle()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        cuts[5] = _cut(address(new Receive()));
        (init, initCalldata) =
            _withUpgradeableIntrospection(address(new TWAPOracleInit()), abi.encodeCall(TWAPOracleInit.init, (admin)));
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
