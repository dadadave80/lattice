// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessManager} from "@lattice/access/AccessManager.sol";
import {AccessManagerInit} from "@lattice/access/AccessManagerInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployAccessManager
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an AccessManager authority diamond: `ERC165Facet` + `AccessManager` +
///         {AccessManagerInit}. The AccessManager self-gates its admin surface on its own `ADMIN_ROLE` (no
///         AccessControl facet needed); `admin` receives that initial role. This diamond is both a standalone
///         authority and the authority backing {DeployAccessManaged}.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployAccessManager is BaseDeploy {
    /// @notice Builds the AccessManager diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted the initial `ADMIN_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessManager).
    /// @return init The {MultiInit} running {AccessManagerInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = _coreCuts();
        (init, initCalldata) = _withImmutableIntrospection(
            address(new AccessManagerInit()), abi.encodeCall(AccessManagerInit.init, (admin))
        );
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `upgradeAdmin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address admin, address upgradeAdmin)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        FacetCut[] memory base = _coreCuts();
        cuts = new FacetCut[](base.length + 2);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        cuts[base.length] = _cut(address(new AccessControl()));
        cuts[base.length + 1] = _cut(address(new AccessControlDiamondCut()));
        (init, initCalldata) = _withAdminUpgradeableIntrospection(
            address(new AccessManagerInit()), abi.encodeCall(AccessManagerInit.init, (admin)), upgradeAdmin
        );
    }

    /// @dev The shared cut set of both overloads: the module facets plus {DiamondLoupeFacet} (introspection).
    function _coreCuts() internal returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessManager()));
        cuts[2] = _cut(address(new DiamondLoupeFacet()));
    }

    /// @notice Deploys an AccessManager authority diamond (broadcasting entrypoint for `forge script`).
    /// @param admin The initial admin.
    /// @return manager The deployed AccessManager diamond address.
    function run(address admin) external returns (address manager) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        manager = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `upgradeAdmin` can `diamondCut`.
    function run(address admin, address upgradeAdmin) external returns (address manager) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, upgradeAdmin);
        manager = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
