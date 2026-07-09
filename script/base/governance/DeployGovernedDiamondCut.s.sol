// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {GovernedDiamondCut} from "@lattice/governance/GovernedDiamondCut.sol";
import {GovernedDiamondCutInit} from "@lattice/governance/GovernedDiamondCutInit.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";

/// @title DeployGovernedDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a governed diamond-cut diamond: `ERC165Facet` + `DiamondLoupeFacet` +
///         `AccessControl` + `EmergencyStop` + `GovernedDiamondCut` + {GovernedDiamondCutInit}. The ONE
///         source of truth for what a governed-cut diamond is, shared by production (`run --broadcast`) and
///         the facet tests (which build on {buildCuts}). The cut facet OWNS the canonical `diamondCut`
///         selector `0x1f931c1c`, gated by EmergencyStop + `UPGRADE_EXECUTOR_ROLE`; `AccessControl` +
///         `EmergencyStop` are part of the base recipe because the emergency + guardian surface is
///         role-gated, and `DiamondLoupeFacet` exposes `facetAddress` so tests can verify an applied cut.
contract DeployGovernedDiamondCut is BaseDeploy {
    /// @notice Builds the governed-cut diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (manages guardians and resumes operation).
    /// @return cuts The facet cuts (ERC165 + Loupe + AccessControl + EmergencyStop + GovernedDiamondCut).
    /// @return init The {GovernedDiamondCutInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new DiamondLoupeFacet()), "DiamondLoupeFacet");
        cuts[2] = _cut(address(new AccessControl()));
        cuts[3] = _cut(address(new EmergencyStop()));
        cuts[4] = _cut(address(new GovernedDiamondCut()));
        init = address(new GovernedDiamondCutInit());
        initCalldata = abi.encodeCall(GovernedDiamondCutInit.init, (admin));
    }

    /// @notice Deploys a governed-cut diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The governance admin.
    /// @return governedDiamond The deployed governed-cut diamond address.
    function run(address admin) external returns (address governedDiamond) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        governedDiamond = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
