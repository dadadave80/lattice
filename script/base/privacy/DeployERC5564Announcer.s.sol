// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {ERC5564Announcer} from "@lattice/privacy/ERC5564Announcer.sol";
import {ERC5564AnnouncerInit} from "@lattice/privacy/ERC5564AnnouncerInit.sol";

/// @title DeployERC5564Announcer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-5564 stealth-address announcer diamond: `ERC165Facet` +
///         `ERC5564Announcer` + {ERC5564AnnouncerInit}. The ONE source of truth for what an announcer diamond is,
///         shared by production (`run --broadcast`) and the facet tests (which build on {buildCuts}). No
///         AccessControl is cut because `announce` is permissionless (any caller may emit an announcement).
contract DeployERC5564Announcer is BaseDeploy {
    /// @notice Builds the ERC-5564 announcer diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @return cuts The facet cuts (ERC165 + ERC5564Announcer).
    /// @return init The {ERC5564AnnouncerInit} initializer address.
    /// @return initCalldata The `init()` calldata.
    function buildCuts() public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](2);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new ERC5564Announcer()));
        init = address(new ERC5564AnnouncerInit());
        initCalldata = abi.encodeCall(ERC5564AnnouncerInit.init, ());
    }

    /// @notice Deploys an ERC-5564 announcer diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @return announcer The deployed announcer diamond address.
    function run() external returns (address announcer) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts();
        announcer = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
