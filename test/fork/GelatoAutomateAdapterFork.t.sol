// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GelatoAutomateAdapter} from "@lattice/oracles/gelato/GelatoAutomateAdapter.sol";
import {GelatoAutomateAdapterLib} from "@lattice/oracles/libraries/GelatoAutomateAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCK CONTRACT
// ---------------------------------------------------------------------------

/// @notice Mock Diamond that combines AccessControl + GelatoAutomateAdapter.
contract MockGelatoAutomateForkContract is AccessControl, GelatoAutomateAdapter {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, GelatoAutomateAdapter)
        returns (bytes memory)
    {}

    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        GelatoAutomateAdapterLib.__GelatoAutomateAdapter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

// ---------------------------------------------------------------------------
//                              FORK TESTS
// ---------------------------------------------------------------------------

/// @title GelatoAutomateAdapterFork
/// @notice Fork tests that exercise GelatoAutomateAdapter against the real Gelato
///         Automate contract on Ethereum mainnet.
///
/// Enabling fork tests:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   export GELATO_AUTOMATE=<gelato-automate-address>
///   forge test --match-path "test/fork/*"
///
/// Without GELATO_AUTOMATE set, all tests in this contract are skipped. Live task
/// creation requires Gelato infra and is out of scope here.
contract GelatoAutomateAdapterFork is Test {
    /// @notice Pinned mainnet block for deterministic results (December 2024).
    uint256 constant FORK_BLOCK = 21_500_000;

    /// @notice Placeholder dedicated msg.sender used for the config round-trip.
    address constant DEDICATED_MSG_SENDER = address(0xBEEF);

    MockGelatoAutomateForkContract adapter;
    address admin = address(0x1);
    address gelatoAutomate;

    function setUp() public {
        gelatoAutomate = vm.envOr("GELATO_AUTOMATE", address(0));
        if (gelatoAutomate == address(0)) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", FORK_BLOCK);

        adapter = new MockGelatoAutomateForkContract();
        adapter.initialize(admin);
    }

    /// @notice Configure the adapter with the live Gelato Automate address and a
    ///         placeholder dedicated msg.sender, then assert getConfig round-trips.
    function test_Fork_ConfigRoundTrips() public {
        vm.prank(admin);
        adapter.setConfig(gelatoAutomate, DEDICATED_MSG_SENDER);

        (address storedAutomate, address storedDedicated) = adapter.getConfig();
        assertEq(storedAutomate, gelatoAutomate, "automate mismatch");
        assertEq(storedDedicated, DEDICATED_MSG_SENDER, "dedicatedMsgSender mismatch");
    }
}
