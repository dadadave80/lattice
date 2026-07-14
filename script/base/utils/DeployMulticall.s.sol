// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {Multicall} from "@lattice/utils/Multicall.sol";

/// @title DeployMulticall
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a diamond with batched-call support: `ERC165Facet` + `AccessControl` +
///         the stateless {Multicall} facet, seeded by {AccessControlInit} (`admin` gets DEFAULT_ADMIN_ROLE). The
///         {Multicall} facet batches `delegatecall`s back through the diamond's OWN dispatcher, so a batch can
///         drive any co-cut facet's selectors (here the `AccessControl` role surface) atomically — a batched
///         sub-call therefore sees the outer caller. `buildCuts` is the broadcast-free primitive the facet test
///         reuses; `run` broadcasts.
contract DeployMulticall is BaseDeploy {
    /// @notice Builds the multicall diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessControl + Multicall + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {AccessControlInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new Multicall()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new AccessControlInit()), abi.encodeCall(AccessControlInit.init, (admin))
        );
    }

    /// @notice Deploys a multicall diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The role admin.
    /// @return multicall The deployed diamond address.
    function run(address admin) external returns (address multicall) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        multicall = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
