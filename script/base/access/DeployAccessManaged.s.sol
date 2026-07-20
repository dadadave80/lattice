// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessManaged} from "@lattice/access/AccessManaged.sol";
import {AccessManagedInit} from "@lattice/access/AccessManagedInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployAccessManaged
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a managed diamond: `ERC165Facet` + `AccessManaged` + {AccessManagedInit}.
///         `AccessManaged` defers every authorization decision to an external AccessManager `authority` (deploy
///         one with {DeployAccessManager}); the init pins that authority. The ONE source of truth for what a
///         managed diamond is, shared by production (`run --broadcast`) and the facet tests.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut; deploy a new diamond to change
///      behavior. Use the ADMIN overload (`buildCuts(..., admin)` / `run(..., admin)`) for an upgradeable
///      deployment gated on `DEFAULT_ADMIN_ROLE`.
contract DeployAccessManaged is BaseDeploy {
    /// @notice Builds the AccessManaged diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param authority The AccessManager authority governing this contract.
    /// @return cuts The facet cuts (ERC165 + AccessManaged).
    /// @return init The {MultiInit} running {AccessManagedInit} then {DiamondIntrospectionInit.initImmutable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address authority)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = _coreCuts();
        (init, initCalldata) = _withImmutableIntrospection(
            address(new AccessManagedInit()), abi.encodeCall(AccessManagedInit.init, (authority))
        );
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(address authority, address admin)
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
            address(new AccessManagedInit()), abi.encodeCall(AccessManagedInit.init, (authority)), admin
        );
    }

    /// @dev The shared cut set of both overloads: the module facets plus {DiamondLoupeFacet} (introspection).
    function _coreCuts() internal returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](4);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessManaged()));
        cuts[2] = _cut(address(new DiamondLoupeFacet()));
        cuts[3] = _cut(address(new Receive()));
    }

    /// @notice Deploys a managed diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param authority The AccessManager authority.
    /// @return managed The deployed managed diamond address.
    function run(address authority) external returns (address managed) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(authority);
        managed = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(address authority, address admin) external returns (address managed) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(authority, admin);
        managed = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
