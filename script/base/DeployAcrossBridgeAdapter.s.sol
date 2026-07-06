// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AcrossBridgeAdapter} from "@lattice/crosschain/AcrossBridgeAdapter.sol";
import {AcrossBridgeAdapterInit} from "@lattice/crosschain/AcrossBridgeAdapterInit.sol";

/// @title DeployAcrossBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an Across v3 token-bridge diamond: `ERC165Facet` + `AcrossBridgeAdapter`
///         + {AcrossBridgeAdapterInit}. The ONE source of truth for what an Across adapter diamond is, shared
///         by production (`run --broadcast`) and the facet tests (which build on {buildCuts}). Unlike the CCTP
///         recipe there is NO `AccessControl` cut: the adapter has no admin surface (the SpokePool is wired
///         once at init and Across chain ids are passed raw by callers — no domain table to manage). The
///         reentrancy guard is seeded inside {AcrossBridgeAdapterInit} (storage-only, no facet cut needed).
contract DeployAcrossBridgeAdapter is BaseDeploy {
    /// @notice Builds the Across adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param spokePool The LOCAL chain's canonical Across v3 SpokePool.
    /// @return cuts         The facet cuts (ERC165 + AcrossBridgeAdapter).
    /// @return init         The {AcrossBridgeAdapterInit} initializer address.
    /// @return initCalldata The `init(spokePool)` calldata.
    function buildCuts(address spokePool)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](2);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AcrossBridgeAdapter()), "AcrossBridgeAdapter");
        init = address(new AcrossBridgeAdapterInit());
        initCalldata = abi.encodeCall(AcrossBridgeAdapterInit.init, (spokePool));
    }

    /// @notice Deploys an Across adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param spokePool The LOCAL chain's canonical Across v3 SpokePool.
    /// @return adapter The deployed Across adapter diamond address.
    function run(address spokePool) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(spokePool);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
