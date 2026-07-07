// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessManaged} from "@lattice/access/AccessManaged.sol";
import {AccessManagedInit} from "@lattice/access/AccessManagedInit.sol";

/// @title DeployAccessManaged
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a managed diamond: `ERC165Facet` + `AccessManaged` + {AccessManagedInit}.
///         `AccessManaged` defers every authorization decision to an external AccessManager `authority` (deploy
///         one with {DeployAccessManager}); the init pins that authority. The ONE source of truth for what a
///         managed diamond is, shared by production (`run --broadcast`) and the facet tests.
contract DeployAccessManaged is BaseDeploy {
    /// @notice Builds the AccessManaged diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param authority The AccessManager authority governing this contract.
    /// @return cuts The facet cuts (ERC165 + AccessManaged).
    /// @return init The {AccessManagedInit} initializer address.
    /// @return initCalldata The `init(authority)` calldata.
    function buildCuts(address authority)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](2);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessManaged()), "AccessManaged");
        init = address(new AccessManagedInit());
        initCalldata = abi.encodeCall(AccessManagedInit.init, (authority));
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
}
