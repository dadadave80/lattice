// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {EmergencyStopInit} from "@lattice/security/EmergencyStopInit.sol";

/// @title DeployEmergencyStop
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an EmergencyStop diamond: `ERC165Facet` + `AccessControl` +
///         `EmergencyStop` + {EmergencyStopInit}. The ONE source of truth for what an emergency-stop diamond is,
///         shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}).
///         `AccessControl` is part of the base recipe because guardian management + `emergencyResume` are
///         `DEFAULT_ADMIN_ROLE`-gated (guardians hold the separate `EMERGENCY_GUARDIAN_ROLE`).
contract DeployEmergencyStop is BaseDeploy {
    /// @notice Builds the EmergencyStop diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (manages guardians and resumes operation).
    /// @return cuts The facet cuts (ERC165 + AccessControl + EmergencyStop).
    /// @return init The {EmergencyStopInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new EmergencyStop()));
        init = address(new EmergencyStopInit());
        initCalldata = abi.encodeCall(EmergencyStopInit.init, (admin));
    }

    /// @notice Deploys an EmergencyStop diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The emergency-stop admin.
    /// @return emergency The deployed emergency-stop diamond address.
    function run(address admin) external returns (address emergency) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        emergency = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
