// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {HyperlaneGatewayAdapter} from "@lattice/crosschain/HyperlaneGatewayAdapter.sol";
import {HyperlaneGatewayAdapterInit} from "@lattice/crosschain/HyperlaneGatewayAdapterInit.sol";

/// @title DeployHyperlaneGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a Hyperlane gateway-adapter diamond: `ERC165Facet` + `AccessControl` +
///         `HyperlaneGatewayAdapter` + {HyperlaneGatewayAdapterInit}. The ONE source of truth for what a
///         Hyperlane adapter diamond is, shared by production (`run --broadcast`) and the facet tests (which
///         build on {buildCuts}). `AccessControl` is part of the base recipe because every domain / remote /
///         destination setter is `DEFAULT_ADMIN_ROLE`-gated. The Hyperlane Mailbox is wired at init time.
contract DeployHyperlaneGatewayAdapter is BaseDeploy {
    /// @notice Builds the Hyperlane adapter diamond cuts + initializer (no broadcast, no proxy deploy).
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls every adapter setter).
    /// @param mailbox The Hyperlane Mailbox the adapter dispatches to and accepts deliveries from.
    /// @return cuts The facet cuts (ERC165 + AccessControl + HyperlaneGatewayAdapter).
    /// @return init The {HyperlaneGatewayAdapterInit} initializer address.
    /// @return initCalldata The `init(admin, mailbox)` calldata.
    function buildCuts(address admin, address mailbox)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new HyperlaneGatewayAdapter()));
        init = address(new HyperlaneGatewayAdapterInit());
        initCalldata = abi.encodeCall(HyperlaneGatewayAdapterInit.init, (admin, mailbox));
    }

    /// @notice Deploys a Hyperlane adapter diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    /// @param admin The adapter admin.
    /// @param mailbox The Hyperlane Mailbox.
    /// @return adapter The deployed Hyperlane adapter diamond address.
    function run(address admin, address mailbox) external returns (address adapter) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(admin, mailbox);
        adapter = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }
}
