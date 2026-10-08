// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {OracleGuard} from "@lattice/oracles/OracleGuard.sol";
import {OracleGuardInit} from "@lattice/oracles/OracleGuardInit.sol";

/// @title DeployOracleGuard
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a standalone OracleGuard diamond: `ERC165Facet` + `AccessControl` +
///         `OracleGuard` + {OracleGuardInit} + {AccessControlInit}. The guard reads the adapter diamond each key is
///         configured with, so it fronts any existing Lattice price adapter without touching it. To guard an
///         adapter in place instead, cut the `OracleGuard` facet into the adapter's diamond, run {OracleGuardInit}
///         next to the adapter's init, and configure keys with that diamond as the oracle. `AccessControl` is
///         part of the base recipe because every setter is `DEFAULT_ADMIN_ROLE`-gated. No `Receive`: the guard
///         never holds value.
contract DeployOracleGuard is BaseDeploy {
    /// @notice Builds the OracleGuard diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessControl + OracleGuard + DiamondLoupeFacet +
    ///         AccessControlDiamondCut).
    /// @return init The {MultiInit} running {OracleGuardInit}, {AccessControlInit}, then
    ///         {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new OracleGuard()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            address(new OracleGuardInit()), abi.encodeCall(OracleGuardInit.init, ()), admin
        );
    }

    /// @notice Deploys an OracleGuard diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The guard admin.
    /// @return guard The deployed OracleGuard diamond address.
    function run(address admin) external returns (address guard) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        guard = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
