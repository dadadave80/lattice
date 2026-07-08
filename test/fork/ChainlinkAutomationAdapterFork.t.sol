// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ChainlinkAutomationAdapter} from "@lattice/oracles/ChainlinkAutomationAdapter.sol";
import {ChainlinkAutomationAdapterLib} from "@lattice/oracles/libraries/ChainlinkAutomationAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCK CONTRACT
// ---------------------------------------------------------------------------

/// @notice Mock Diamond that combines AccessControl + ChainlinkAutomationAdapter.
contract MockChainlinkAutomationAdapterForkContract is AccessControl, ChainlinkAutomationAdapter {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, ChainlinkAutomationAdapter)
        returns (bytes memory)
    {}

    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        ChainlinkAutomationAdapterLib.__ChainlinkAutomationAdapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              FORK TESTS
// ---------------------------------------------------------------------------

/// @title ChainlinkAutomationAdapterFork
/// @notice Fork tests that exercise ChainlinkAutomationAdapter config round-trip
///         against a real Chainlink Automation forwarder on Ethereum mainnet.
///
/// Enabling fork tests:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   export CHAINLINK_AUTOMATION_FORWARDER=<forwarder-address>
///   forge test --match-path "test/fork/*"
///
/// Without CHAINLINK_AUTOMATION_FORWARDER set, all tests here are skipped.
/// The forwarder-driven `performUpkeep` flow is off-chain, so this verifies the
/// on-chain configuration round-trip only.
contract ChainlinkAutomationAdapterFork is Test {
    /// @notice Pinned mainnet block for deterministic results (December 2024).
    uint256 constant FORK_BLOCK = 21_500_000;

    uint256 constant INTERVAL = 1 hours;

    MockChainlinkAutomationAdapterForkContract automation;
    address admin = address(0x1);
    address forwarder;

    function setUp() public {
        forwarder = vm.envOr("CHAINLINK_AUTOMATION_FORWARDER", address(0));
        if (forwarder == address(0)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", FORK_BLOCK);

        automation = new MockChainlinkAutomationAdapterForkContract();
        automation.initialize(admin);
    }

    /// @notice Configure the real forwarder and verify the config round-trips.
    function test_Fork_ForwarderConfigRoundTrip() public {
        vm.prank(admin);
        automation.setConfig(forwarder, INTERVAL);

        assertEq(automation.getForwarder(), forwarder, "forwarder mismatch");
        assertEq(automation.getInterval(), INTERVAL, "interval mismatch");
        assertEq(automation.getLastTimeStamp(), block.timestamp, "lastTimeStamp not reset");
    }
}
