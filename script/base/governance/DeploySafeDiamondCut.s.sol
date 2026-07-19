// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {SafeDiamondCut} from "@lattice/governance/SafeDiamondCut.sol";
import {SafeDiamondCutInit} from "@lattice/governance/SafeDiamondCutInit.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";

/// @title DeploySafeDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Safe-gated diamond-cut diamond: `ERC165Facet` + `DiamondLoupeFacet`
///         + `AccessControl` + `EmergencyStop` + `SafeDiamondCut` + {SafeDiamondCutInit}. The ONE source of
///         truth for what a Safe-gated cut diamond is, shared by production (`run --broadcast`) and the
///         facet tests (which build on {buildCuts}). The cut facet OWNS the canonical `diamondCut` selector
///         `0x1f931c1c`, gated by EmergencyStop + the pinned Safe; `AccessControl` + `EmergencyStop` are part
///         of the base recipe because the emergency + guardian surface is role-gated, and `DiamondLoupeFacet`
///         exposes `facetAddress` so tests can verify an applied cut.
contract DeploySafeDiamondCut is BaseDeploy {
    /// @notice Builds the Safe-gated cut diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (manages guardians and resumes operation).
    /// @param safe The Gnosis Safe multisig pinned as the sole cut authority.
    /// @param minThreshold The minimum signature threshold the pinned Safe must enforce.
    /// @return cuts The facet cuts (ERC165 + Loupe + AccessControl + EmergencyStop + SafeDiamondCut).
    /// @return init The {SafeDiamondCutInit} initializer address.
    /// @return initCalldata The `init(admin, safe, minThreshold)` calldata.
    function buildCuts(address admin, address safe, uint256 minThreshold)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new DiamondLoupeFacet()), "DiamondLoupeFacet");
        cuts[2] = _cut(address(new AccessControl()));
        cuts[3] = _cut(address(new EmergencyStop()));
        cuts[4] = _cut(address(new SafeDiamondCut()));
        cuts[5] = _cut(address(new Receive()));
        init = address(new SafeDiamondCutInit());
        initCalldata = abi.encodeCall(SafeDiamondCutInit.init, (admin, safe, minThreshold));
    }

    /// @notice Deploys a Safe-gated cut diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The governance admin.
    /// @param safe The pinned Safe authority.
    /// @param minThreshold The minimum Safe signature threshold.
    /// @return safeDiamond The deployed Safe-gated cut diamond address.
    function run(address admin, address safe, uint256 minThreshold) external returns (address safeDiamond) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, safe, minThreshold);
        safeDiamond = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
