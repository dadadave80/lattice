// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ArchiveFork} from "@lattice-test/helpers/ArchiveFork.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Exposes {ArchiveFork}'s internal guards so their outcomes can be asserted at an external call boundary.
contract ArchiveForkHarness {
    function isPruned(bytes memory err) external pure returns (bool) {
        return ArchiveFork.isPruned(err);
    }

    function skipOrFail(bool strict, string memory reason) external {
        ArchiveFork.skipOrFail(strict, reason);
    }
}

/// @title ArchiveForkTest
/// @notice Offline checks of the fork-suite guards: which RPC errors count as pruned history, and the strict mode
///         that the weekly fork lanes run under (`FORK_REQUIRE_ARCHIVE=true`), where a guard fails instead of
///         skipping. The non-strict branch marks the calling test skipped, so only the strict branch is asserted.
contract ArchiveForkTest is Test {
    ArchiveForkHarness internal harness;

    function setUp() public {
        harness = new ArchiveForkHarness();
    }

    /// @notice EIP-4444 history expiry, as `sepolia.base.org` answers for a block below its retention window.
    function test_IsPruned_Eip4444HistoryExpiry() public view {
        assertTrue(
            harness.isPruned(
                bytes("error code 4444: pruned history unavailable (earliest available block is 46000000)")
            )
        );
    }

    /// @notice A reth full node that dropped the state at the block. The public Arc testnet endpoints answer this
    ///         way for CCTPUSDCDemoFork's pinned Arc block; before the state probe it surfaced as a setUp revert.
    function test_IsPruned_RethPrunedState() public view {
        assertTrue(
            harness.isPruned(
                bytes(
                    "vm.rpc: \"eth_getBalance\": server returned an error response: error code -32603: state at block #52000001 is pruned"
                )
            )
        );
    }

    /// @notice A geth node that no longer keeps the historical state.
    function test_IsPruned_GethMissingHistoricalState() public view {
        assertTrue(harness.isPruned(bytes("historical state 0x3f1a is not available")));
        assertTrue(harness.isPruned(bytes("missing trie node 9a3c (path ) state 0x3f1a is not available")));
    }

    /// @notice Errors that say nothing about pruned history still fail the test.
    function test_IsPruned_FalseForOtherErrors() public view {
        assertFalse(harness.isPruned(bytes("execution reverted")));
        assertFalse(harness.isPruned(bytes("HTTP error 429: rate limit exceeded")));
        assertFalse(harness.isPruned(bytes("")));
    }

    /// @notice In strict mode a guard that would skip fails with its reason, so a lane cannot pass by skipping.
    function test_SkipOrFail_StrictReverts() public {
        vm.expectRevert(abi.encodeWithSelector(ArchiveFork.ArchiveFork__SkipRefused.selector, "fixture is empty"));
        harness.skipOrFail(true, "fixture is empty");
    }
}
