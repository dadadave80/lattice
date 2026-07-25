// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployCCTPBridgeAdapter} from "@lattice-script/base/crosschain/DeployCCTPBridgeAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {CCTPBridgeAdapter} from "@lattice/crosschain/circle/CCTPBridgeAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title CCTPBridgeAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for CCTP token-bridge adapter facet tests that exercise a REAL {Diamond} rather than a
///         flattened inheritance mock. `_deployCCTPBridgeAdapter` assembles the production
///         {DeployCCTPBridgeAdapter} recipe (ERC165 + AccessControl + CCTPBridgeAdapter + {CCTPBridgeAdapterInit})
///         with the CCTP TokenMessenger / MessageTransmitter / USDC wired at init — so every burn / relay /
///         config call routes through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs
///         a mock hides. The external `MockTokenMessenger`, `MockMessageTransmitter` and `MockUSDC` stay test
///         fixtures (they are NOT the facet under test). The zero-address init guard is exercised by calling
///         `_deployCCTPBridgeAdapter` with a zero address inside `vm.expectRevert` (the `CCTPZeroAddress` revert
///         bubbles up through {Diamond.initialize}).
abstract contract CCTPBridgeAdapterTestBase is Test, GetSelectors {
    DeployCCTPBridgeAdapter internal deployer;

    /// @notice Assembles the production CCTP adapter diamond with `admin` as the adapter admin.
    /// @param admin              The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param tokenMessenger     The CCTP TokenMessenger (mock in tests).
    /// @param messageTransmitter The CCTP MessageTransmitter (mock in tests).
    /// @param usdc               The USDC token (mock in tests).
    /// @return diamond_ The deployed CCTP adapter diamond.
    function _deployCCTPBridgeAdapter(address admin, address tokenMessenger, address messageTransmitter, address usdc)
        internal
        returns (address diamond_)
    {
        deployer = new DeployCCTPBridgeAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            deployer.buildCuts(admin, tokenMessenger, messageTransmitter, usdc);

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}
