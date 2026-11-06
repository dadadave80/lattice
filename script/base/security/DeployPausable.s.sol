// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {PausableInit} from "@lattice/security/PausableInit.sol";

/// @title DeployPausable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Pausable diamond: `ERC165Facet` + `AccessControl` + `Pausable` +
///         its released initializer. The ONE source of truth for what a pausable diamond is, shared by production
///         (`run --broadcast`) and the facet tests (which build on {buildCuts}). `AccessControl` is part of the
///         base recipe because `pause()`/`unpause()` are `DEFAULT_ADMIN_ROLE`-gated.
contract DeployPausable is BaseDeploy {
    /// @notice Builds the Pausable diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls pause/unpause).
    /// @return cuts The facet cuts (ERC165 + AccessControl + Pausable + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {PausableInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(_facet("ERC165Facet"));
        cuts[1] = _cut(_facet("AccessControl"));
        cuts[2] = _cut(_facet("Pausable"));
        cuts[3] = _cut(_facet("DiamondLoupeFacet"));
        cuts[4] = _cut(_facet("AccessControlDiamondCut"));
        (init, initCalldata) =
            _withUpgradeableIntrospection(_init("PausableInit"), abi.encodeCall(PausableInit.init, (admin)));
    }

    /// @notice Deploys a Pausable diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The pause admin.
    /// @return pausable The deployed pausable diamond address.
    function run(address admin) external returns (address pausable) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        pausable = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
