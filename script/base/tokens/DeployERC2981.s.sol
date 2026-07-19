// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {ERC2981} from "@lattice/tokens/ERC2981/ERC2981.sol";
import {ERC2981Init} from "@lattice/tokens/ERC2981/ERC2981Init.sol";

/// @title DeployERC2981
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-2981 royalty diamond: `ERC165Facet` + `AccessControl` + `ERC2981`
///         + {ERC2981Init}. The ONE source of truth for what a royalty diamond is, shared by production
///         (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is part of the
///         base recipe because every royalty setter is `DEFAULT_ADMIN_ROLE`-gated.
contract DeployERC2981 is BaseDeploy {
    /// @notice Builds the ERC-2981 royalty diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls the royalty setters).
    /// @return cuts The facet cuts (ERC165 + AccessControl + ERC2981 + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {ERC2981Init} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new ERC2981()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        cuts[5] = _cut(address(new Receive()));
        (init, initCalldata) =
            _withUpgradeableIntrospection(address(new ERC2981Init()), abi.encodeCall(ERC2981Init.init, (admin)));
    }

    /// @notice Deploys an ERC-2981 royalty diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The royalty admin.
    /// @return royalty The deployed royalty diamond address.
    function run(address admin) external returns (address royalty) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        royalty = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
