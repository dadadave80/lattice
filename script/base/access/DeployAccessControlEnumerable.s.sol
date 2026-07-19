// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControlEnumerable} from "@lattice/access/AccessControlEnumerable.sol";
import {AccessControlEnumerableInit} from "@lattice/access/AccessControlEnumerableInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";

/// @title DeployAccessControlEnumerable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for the enumerable role diamond: `ERC165Facet` + `AccessControlEnumerable` +
///         {AccessControlEnumerableInit}. `AccessControlEnumerable` is a drop-in AccessControl FLAVOR carrying the
///         full role surface PLUS per-role member enumeration, so it is cut in place of the base `AccessControl`
///         facet (cutting both would collide on the shared role selectors).
contract DeployAccessControlEnumerable is BaseDeploy {
    /// @notice Builds the AccessControlEnumerable diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessControlEnumerable + DiamondLoupeFacet + AccessControlDiamondCut).
    /// @return init The {MultiInit} running {AccessControlEnumerableInit} then {DiamondIntrospectionInit.initUpgradeable}.
    /// @return initCalldata The matching `multiInit` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControlEnumerable()));
        cuts[2] = _cut(address(new DiamondLoupeFacet()));
        cuts[3] = _cut(address(new AccessControlDiamondCut()));
        cuts[4] = _cut(address(new Receive()));
        (init, initCalldata) = _withUpgradeableIntrospection(
            address(new AccessControlEnumerableInit()), abi.encodeCall(AccessControlEnumerableInit.init, (admin))
        );
    }

    /// @notice Deploys an AccessControlEnumerable diamond (broadcasting entrypoint for `forge script`).
    /// @param admin The role admin.
    /// @return accessControl The deployed AccessControlEnumerable diamond address.
    function run(address admin) external returns (address accessControl) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        accessControl = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
