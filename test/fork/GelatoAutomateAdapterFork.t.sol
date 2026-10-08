// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GelatoAutomateAdapter} from "@lattice/oracles/gelato/GelatoAutomateAdapter.sol";
import {GelatoAutomateAdapterLib} from "@lattice/oracles/gelato/GelatoAutomateAdapterLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCK CONTRACT
// ---------------------------------------------------------------------------

/// @notice Mock Diamond that combines AccessControl + GelatoAutomateAdapter.
contract MockGelatoAutomateForkContract is AccessControl, GelatoAutomateAdapter, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, GelatoAutomateAdapter)
        returns (bytes memory)
    {}

    function initialize(address _admin) external initializer {
        AccessControlLib.__AccessControl_init(_admin);
        GelatoAutomateAdapterLib.__GelatoAutomateAdapter_init();
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
///   forge test --match-path "test/fork/GelatoAutomateAdapterFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests in this contract are skipped.
/// GELATO_AUTOMATE overrides the canonical Automate address. Live task creation
/// requires Gelato infra and is out of scope here.
contract GelatoAutomateAdapterFork is Test {
    /// @notice Pinned mainnet block for deterministic results (December 2024).
    uint256 constant FORK_BLOCK = 21_500_000;

    /// @notice Gelato Automate proxy on Ethereum mainnet (`version()` "7" at FORK_BLOCK).
    address constant AUTOMATE = 0x2A6C106ae13B558BB9E2Ec64Bd2f1f7BEFF3A5E0;
    /// @notice The Gelato diamond that Automate's `gelato()` reports at FORK_BLOCK.
    address constant GELATO_DIAMOND = 0x3CACa7b48D0573D793d3b0279b5F0029180E83b6;

    /// @notice Placeholder dedicated msg.sender used for the config round-trip.
    address constant DEDICATED_MSG_SENDER = address(0xBEEF);

    MockGelatoAutomateForkContract adapter;
    address admin = address(0x1);
    address gelatoAutomate;

    function setUp() public {
        if (bytes(vm.envOr("MAINNET_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        gelatoAutomate = vm.envOr("GELATO_AUTOMATE", AUTOMATE);
        vm.createSelectFork("mainnet", FORK_BLOCK);

        adapter = new MockGelatoAutomateForkContract();
        adapter.initialize(admin);
    }

    /// @notice The default address is the live Automate proxy, wired to the Gelato diamond.
    function test_Fork_DefaultAutomateIsLive() public view {
        (bool ok, bytes memory ret) = AUTOMATE.staticcall(abi.encodeWithSignature("gelato()"));
        assertTrue(ok, "gelato() reverted");
        assertEq(abi.decode(ret, (address)), GELATO_DIAMOND, "Automate reports another Gelato diamond");
    }

    /// @notice Configure the adapter with the live Gelato Automate address and a
    ///         placeholder dedicated msg.sender, then assert getConfig round-trips.
    function test_Fork_ConfigRoundTrips() public {
        assertGt(gelatoAutomate.code.length, 0, "no Automate code at the fork block");
        vm.prank(admin);
        adapter.setConfig(gelatoAutomate, DEDICATED_MSG_SENDER);

        (address storedAutomate, address storedDedicated) = adapter.getConfig();
        assertEq(storedAutomate, gelatoAutomate, "automate mismatch");
        assertEq(storedDedicated, DEDICATED_MSG_SENDER, "dedicatedMsgSender mismatch");
    }
}
