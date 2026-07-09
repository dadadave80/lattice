// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {GovernedSafeDiamondCut} from "@lattice/governance/GovernedSafeDiamondCut.sol";
import {GovernedSafeDiamondCutInit} from "@lattice/governance/GovernedSafeDiamondCutInit.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";

/// @title DeployGovernedSafeDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Safe-gated, timelocked diamond-cut diamond: `ERC165Facet` +
///         `DiamondLoupeFacet` + `AccessControl` + `EmergencyStop` + `GovernedSafeDiamondCut` +
///         {GovernedSafeDiamondCutInit}. The ONE source of truth for what a governed-Safe-cut diamond is,
///         shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}). Unlike
///         {SafeDiamondCut} the facet deliberately does NOT serve the synchronous cut selector `0x1f931c1c`
///         (every cut is scheduled, matures past `minDelay`, then executed by the pinned Safe);
///         `AccessControl` + `EmergencyStop` are part of the base recipe because the emergency + guardian
///         surface is role-gated, and `DiamondLoupeFacet` exposes `facetAddress` so tests can verify an
///         applied cut.
contract DeployGovernedSafeDiamondCut is BaseDeploy {
    /// @notice Builds the governed-Safe-cut diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (manages guardians and resumes operation).
    /// @param safe The Gnosis Safe multisig pinned as the sole scheduling/execution authority.
    /// @param minThreshold The minimum signature threshold the pinned Safe must enforce.
    /// @param minDelay The minimum timelock delay (seconds) between schedule and execute.
    /// @return cuts The facet cuts (ERC165 + Loupe + AccessControl + EmergencyStop + GovernedSafeDiamondCut).
    /// @return init The {GovernedSafeDiamondCutInit} initializer address.
    /// @return initCalldata The `init(admin, safe, minThreshold, minDelay)` calldata.
    function buildCuts(address admin, address safe, uint256 minThreshold, uint256 minDelay)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new DiamondLoupeFacet()), "DiamondLoupeFacet");
        cuts[2] = _cut(address(new AccessControl()));
        cuts[3] = _cut(address(new EmergencyStop()));
        cuts[4] = _cut(address(new GovernedSafeDiamondCut()));
        init = address(new GovernedSafeDiamondCutInit());
        initCalldata = abi.encodeCall(GovernedSafeDiamondCutInit.init, (admin, safe, minThreshold, minDelay));
    }

    /// @notice Deploys a governed-Safe-cut diamond (broadcasting entrypoint for `forge script ...
    ///         --broadcast`).
    /// @param admin The governance admin.
    /// @param safe The pinned Safe authority.
    /// @param minThreshold The minimum Safe signature threshold.
    /// @param minDelay The minimum timelock delay (seconds).
    /// @return governedSafeDiamond The deployed governed-Safe-cut diamond address.
    function run(address admin, address safe, uint256 minThreshold, uint256 minDelay)
        external
        returns (address governedSafeDiamond)
    {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(admin, safe, minThreshold, minDelay);
        governedSafeDiamond = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
