// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {PythEntropyAdapter} from "@lattice/oracles/PythEntropyAdapter.sol";
import {PythEntropyAdapterInit} from "@lattice/oracles/PythEntropyAdapterInit.sol";

/// @title DeployPythEntropyAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Pyth Entropy randomness diamond: `ERC165Facet` + `AccessControl` +
///         `PythEntropyAdapter` + {PythEntropyAdapterInit}. The ONE source of truth for what an entropy diamond
///         is, shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because every config/request setter is admin-gated.
contract DeployPythEntropyAdapter is BaseDeploy {
    /// @notice Builds the Pyth Entropy diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the entropy config + request setters).
    /// @return cuts The facet cuts (ERC165 + AccessControl + PythEntropyAdapter).
    /// @return init The {PythEntropyAdapterInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new PythEntropyAdapter()), "PythEntropyAdapter");
        init = address(new PythEntropyAdapterInit());
        initCalldata = abi.encodeCall(PythEntropyAdapterInit.init, (admin));
    }

    /// @notice Deploys a Pyth Entropy diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The entropy admin.
    /// @return entropy The deployed entropy diamond address.
    function run(address admin) external returns (address entropy) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        entropy = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
