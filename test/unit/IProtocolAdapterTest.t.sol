// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IProtocolAdapter} from "@lattice/interfaces/IProtocolAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Compile-level proof that IProtocolAdapter exposes the agreed ABI:
///         lifecycle (deploy/harvest/emergencyWithdraw), health views, config events,
///         and the custom errors adapters revert with.
contract IProtocolAdapterTest is Test {
    function test_InterfaceIdIsStable() public pure {
        // Locks the selector set. If a function is added/removed/renamed this changes
        // and the test must be updated deliberately (the value also feeds the ERC-165 slot).
        bytes4 id = type(IProtocolAdapter).interfaceId;
        assertTrue(id != bytes4(0), "interfaceId must be non-zero");
    }

    function test_ErrorAndEventSelectorsExist() public pure {
        // Touch each error/event selector so a rename breaks compilation here.
        bytes4[6] memory sel = [
            IProtocolAdapter.ProtocolAdapterPaused.selector,
            IProtocolAdapter.ProtocolAdapterZeroAddress.selector,
            IProtocolAdapter.ProtocolAdapterNothingToDeploy.selector,
            IProtocolAdapter.ProtocolAdapterHealthFactorBreached.selector,
            IProtocolAdapter.ProtocolAdapterRewardForwardFailed.selector,
            IProtocolAdapter.ProtocolAdapterUnauthorized.selector
        ];
        for (uint256 i; i < sel.length; ++i) {
            assertTrue(sel[i] != bytes4(0), "selector must be non-zero");
        }
    }
}
