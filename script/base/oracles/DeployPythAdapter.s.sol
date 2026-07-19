// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {PythAdapter} from "@lattice/oracles/pyth/PythAdapter.sol";
import {PythAdapterInit} from "@lattice/oracles/pyth/PythAdapterInit.sol";

/// @title DeployPythAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Pyth price-feed adapter diamond: `ERC165Facet` + `AccessControl` +
///         `PythAdapter` + {PythAdapterInit}. The ONE source of truth for what a Pyth adapter diamond is, shared
///         by production (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is
///         part of the base recipe because the feed-registry setters and `setPyth` are `DEFAULT_ADMIN_ROLE`-gated.
///         Unlike the registry-only adapters, the Pyth contract reference is wired at init time.
contract DeployPythAdapter is BaseDeploy {
    /// @notice Builds the Pyth adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the feed registry and `setPyth`).
    /// @param pyth The Pyth contract the adapter reads prices from and forwards update fees to.
    /// @return cuts The facet cuts (ERC165 + AccessControl + PythAdapter + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {PythAdapterInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin, address pyth)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new PythAdapter()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new PythAdapterInit()), abi.encodeCall(PythAdapterInit.init, (admin, pyth))
        );
    }

    /// @notice Deploys a Pyth adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The feed-registry admin.
    /// @param pyth The Pyth contract reference.
    /// @return adapter The deployed Pyth adapter diamond address.
    function run(address admin, address pyth) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, pyth);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
