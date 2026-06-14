// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAdapterOperator} from "@lattice/interfaces/IAdapterOperator.sol";
import {IProtocolAdapter} from "@lattice/interfaces/IProtocolAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Compile-level proof that IProtocolAdapter exposes the agreed ABI:
///         lifecycle (deploy/harvest/emergencyWithdraw), health views, config events,
///         and the custom errors adapters revert with.
contract IProtocolAdapterTest is Test {
    function test_InterfaceIdIsStable() public pure {
        // Pins the EXACT selector set. The operator surface lives in the SEPARATE IAdapterOperator
        // interface precisely so this id stays frozen at 0x8f7783e6 (it feeds the ERC-165 map slot
        // registered by every adapter; changing it would silently break ERC-165 discovery). Errors
        // and events do NOT affect a Solidity interfaceId, so the OperatorSet event and the
        // Unauthorized/InvalidRecipient errors added in this change leave the id untouched.
        assertEq(type(IProtocolAdapter).interfaceId, bytes4(0x8f7783e6), "IProtocolAdapter id must be pinned");
    }

    function test_ErrorAndEventSelectorsExist() public pure {
        // Touch each ERROR selector (bytes4) so a rename breaks compilation here.
        bytes4[7] memory sel = [
            IProtocolAdapter.ProtocolAdapterPaused.selector,
            IProtocolAdapter.ProtocolAdapterZeroAddress.selector,
            IProtocolAdapter.ProtocolAdapterNothingToDeploy.selector,
            IProtocolAdapter.ProtocolAdapterHealthFactorBreached.selector,
            IProtocolAdapter.ProtocolAdapterRewardForwardFailed.selector,
            IProtocolAdapter.ProtocolAdapterUnauthorized.selector,
            IProtocolAdapter.ProtocolAdapterInvalidRecipient.selector
        ];
        for (uint256 i; i < sel.length; ++i) {
            assertTrue(sel[i] != bytes4(0), "selector must be non-zero");
        }
        // Event topic-0 selectors are bytes32; touch the new one separately.
        assertTrue(IProtocolAdapter.OperatorSet.selector != bytes32(0), "OperatorSet event selector");
        assertTrue(IProtocolAdapter.RewardRecipientSet.selector != bytes32(0), "RewardRecipientSet event selector");
    }

    /// @notice The operator surface is its own interface so its function selectors do NOT bleed into
    ///         the pinned IProtocolAdapter id. Touch them so a rename breaks compilation.
    function test_AdapterOperatorSurfaceExists() public pure {
        assertTrue(type(IAdapterOperator).interfaceId != bytes4(0), "IAdapterOperator id non-zero");
        assertTrue(IAdapterOperator.setOperator.selector != bytes4(0), "setOperator selector");
        assertTrue(IAdapterOperator.operator.selector != bytes4(0), "operator selector");
    }
}
