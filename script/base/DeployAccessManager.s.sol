// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessManager} from "@lattice/access/AccessManager.sol";
import {AccessManagerInit} from "@lattice/access/AccessManagerInit.sol";

/// @title DeployAccessManager
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an AccessManager authority diamond: `ERC165Facet` + `AccessManager` +
///         {AccessManagerInit}. The AccessManager self-gates its admin surface on its own `ADMIN_ROLE` (no
///         AccessControl facet needed); `admin` receives that initial role. This diamond is both a standalone
///         authority and the authority backing {DeployAccessManaged}.
contract DeployAccessManager is BaseDeploy {
    /// @notice Builds the AccessManager diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted the initial `ADMIN_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessManager).
    /// @return init The {AccessManagerInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](2);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessManager()), "AccessManager");
        init = address(new AccessManagerInit());
        initCalldata = abi.encodeCall(AccessManagerInit.init, (admin));
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
}
