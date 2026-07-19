// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployWormholeGatewayAdapter} from "@lattice-script/base/crosschain/DeployWormholeGatewayAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {WormholeGatewayAdapter} from "@lattice/crosschain/wormhole/WormholeGatewayAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title WormholeGatewayAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Wormhole gateway-adapter facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployWormholeGatewayAdapter} recipe (ERC165 +
///         AccessControl + WormholeGatewayAdapter + {WormholeGatewayAdapterInit}) with the Wormhole relayer + local
///         chain id wired at init, and exposes a typed `adapter` handle — so every send / relay / receive / config
///         call routes through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock
///         hides. The external `MockWormholeRelayer` and `MockRecipient` stay test fixtures (NOT the facet under
///         test).
abstract contract WormholeGatewayAdapterTestBase is Test, GetSelectors {
    DeployWormholeGatewayAdapter internal deployer;
    address internal diamond; // the assembled Wormhole adapter diamond
    WormholeGatewayAdapter internal adapter; // typed handle on the diamond (all calls dispatch through it)

    /// @notice Assembles the production Wormhole adapter diamond with `admin` as the adapter admin, wiring `relayer`
    ///         and this chain's `wormholeChainId` at init.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param relayer The Wormhole relayer the adapter dispatches to and accepts deliveries from.
    /// @param wormholeChainId This chain's Wormhole chain id.
    /// @return diamond_ The deployed Wormhole adapter diamond.
    function _deployWormholeGatewayAdapter(address admin, address relayer, uint16 wormholeChainId)
        internal
        returns (address diamond_)
    {
        deployer = new DeployWormholeGatewayAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            deployer.buildCuts(admin, relayer, wormholeChainId);

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
