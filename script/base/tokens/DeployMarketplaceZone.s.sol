// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {MarketplaceZone} from "@lattice/tokens/MarketplaceZone.sol";
import {MarketplaceZoneInit} from "@lattice/tokens/MarketplaceZoneInit.sol";

/// @title DeployMarketplaceZone
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Seaport zone diamond: `ERC165Facet` + `AccessControl` + the
///         {MarketplaceZone} facet, seeded by {MarketplaceZoneInit}. The diamond acts as the `zone` for RESTRICTED
///         Seaport orders — `authorizeOrder` enforces pause + blocklist and `validateOrder` enforces ERC-2981
///         royalties, both gated/configured through the co-cut `AccessControl` role surface (`admin` gets
///         DEFAULT_ADMIN_ROLE). `buildCuts` is the broadcast-free primitive the zone facet test reuses; `run`
///         broadcasts.
contract DeployMarketplaceZone is BaseDeploy {
    /// @notice Builds the marketplace zone diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return cuts The facet cuts (ERC165 + AccessControl + MarketplaceZone).
    /// @return init The {MarketplaceZoneInit} initializer address.
    /// @return initCalldata The `init(admin)` calldata.
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory initCalldata) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new MarketplaceZone()), "MarketplaceZone");
        init = address(new MarketplaceZoneInit());
        initCalldata = abi.encodeCall(MarketplaceZoneInit.init, (admin));
    }

    /// @notice Deploys a marketplace zone diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The role admin.
    /// @return zone The deployed marketplace zone diamond address.
    function run(address admin) external returns (address zone) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin);
        zone = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
