// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ChainlinkAutomationAdapter} from "@lattice/oracles/chainlink/ChainlinkAutomationAdapter.sol";
import {ChainlinkAutomationAdapterLib} from "@lattice/oracles/chainlink/ChainlinkAutomationAdapterLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCK CONTRACT
// ---------------------------------------------------------------------------

/// @notice Mock Diamond that combines AccessControl + ChainlinkAutomationAdapter.
contract MockChainlinkAutomationAdapterForkContract is AccessControl, ChainlinkAutomationAdapter, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, ChainlinkAutomationAdapter)
        returns (bytes memory)
    {}

    function initialize(address _admin) external initializer {
        AccessControlLib.__AccessControl_init(_admin);
        ChainlinkAutomationAdapterLib.__ChainlinkAutomationAdapter_init();
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
///   forge test --match-path "test/fork/ChainlinkAutomationAdapterFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests here are skipped. A forwarder belongs
/// to one upkeep, so the default is the forwarder of a live upkeep on the
/// mainnet Automation Registry 2.1 at the pinned block;
/// CHAINLINK_AUTOMATION_FORWARDER overrides it. The forwarder-driven
/// `performUpkeep` flow is off-chain, so this verifies the on-chain
/// configuration round-trip only.
contract ChainlinkAutomationAdapterFork is Test {
    /// @notice Pinned mainnet block for deterministic results (December 2024).
    uint256 constant FORK_BLOCK = 21_500_000;

    /// @notice Chainlink Automation Registry 2.1 on Ethereum mainnet (`typeAndVersion` "KeeperRegistry 2.1.0").
    address constant REGISTRY_V2_1 = 0x6593c7De001fC8542bB1703532EE1E5aA0D458fD;
    /// @notice `AutomationForwarder 1.0.0` of upkeep
    ///         37139378590340576488101784362222889752237871948060516894495194681064041951097, the first id that
    ///         `REGISTRY_V2_1.getActiveUpkeepIDs(0, 1)` returns at FORK_BLOCK.
    address constant UPKEEP_FORWARDER = 0x4249093e75b2eECA9f3ba3171eA1f3fA186ABE9D;

    uint256 constant INTERVAL = 1 hours;

    MockChainlinkAutomationAdapterForkContract automation;
    address admin = address(0x1);
    address forwarder;

    function setUp() public {
        if (bytes(vm.envOr("MAINNET_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        forwarder = vm.envOr("CHAINLINK_AUTOMATION_FORWARDER", UPKEEP_FORWARDER);
        vm.createSelectFork("mainnet", FORK_BLOCK);

        automation = new MockChainlinkAutomationAdapterForkContract();
        automation.initialize(admin);
    }

    /// @notice The default forwarder is a live AutomationForwarder that reports the mainnet registry 2.1.
    function test_Fork_DefaultForwarderIsRegistryForwarder() public view {
        (bool ok, bytes memory ret) = UPKEEP_FORWARDER.staticcall(abi.encodeWithSignature("getRegistry()"));
        assertTrue(ok, "getRegistry() reverted");
        assertEq(abi.decode(ret, (address)), REGISTRY_V2_1, "forwarder reports another registry");
    }

    /// @notice Configure the real forwarder and verify the config round-trips.
    function test_Fork_ForwarderConfigRoundTrip() public {
        assertGt(forwarder.code.length, 0, "no forwarder code at the fork block");
        vm.prank(admin);
        automation.setConfig(forwarder, INTERVAL);

        assertEq(automation.getForwarder(), forwarder, "forwarder mismatch");
        assertEq(automation.getInterval(), INTERVAL, "interval mismatch");
        assertEq(automation.getLastTimeStamp(), block.timestamp, "lastTimeStamp not reset");
    }
}
