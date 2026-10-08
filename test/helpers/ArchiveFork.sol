// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Vm} from "forge-std/Vm.sol";

/// @title ArchiveFork
/// @notice Forks an RPC alias at a pinned historical block, or skips the test when that RPC has pruned the block.
/// @dev Replay suites pin old blocks (a CCTP receive block minus one, a fixture's source block) that only an
///      archive endpoint keeps. Public endpoints drop history on a rolling window and answer with EIP-4444's
///      `pruned history unavailable` (code 4444). Some prune block bodies, so `createSelectFork` fails; others
///      prune state, so the fork opens and the first account read fails mid-test, which no test can catch. The
///      guard therefore probes state at the block before forking, then catches the fork error. Only the
///      pruned-history error skips; any other error still fails the test. Set `FORK_REQUIRE_ARCHIVE=true` (the
///      scheduled fork workflow does) to fail instead of skipping, so a non-archive secret cannot pass a lane
///      by skipping it. Callers check their `*_RPC_URL` first: an unset alias errors with a different message.
library ArchiveFork {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    bytes private constant PRUNED = "pruned history unavailable";

    /// @notice Selects a fork of `rpcAlias` at `blockNumber`, or skips the test when the RPC pruned that block.
    /// @return forked True when the fork is selected; false when the test was marked skipped.
    function select(string memory rpcAlias, uint256 blockNumber) internal returns (bool forked) {
        string memory params =
            string.concat('["0x0000000000000000000000000000000000000000","', _toHexQuantity(blockNumber), '"]');
        try VM.rpc(rpcAlias, "eth_getBalance", params) {}
        catch (bytes memory err) {
            _skipIfPruned(err, rpcAlias, blockNumber);
            return false;
        }
        try VM.createSelectFork(rpcAlias, blockNumber) {
            return true;
        } catch (bytes memory err) {
            _skipIfPruned(err, rpcAlias, blockNumber);
            return false;
        }
    }

    /// @dev Skips on a pruned-history error (unless `FORK_REQUIRE_ARCHIVE` is set); re-raises anything else.
    function _skipIfPruned(bytes memory err, string memory rpcAlias, uint256 blockNumber) private {
        if (!_contains(err, PRUNED) || VM.envOr("FORK_REQUIRE_ARCHIVE", false)) {
            assembly ("memory-safe") {
                revert(add(err, 0x20), mload(err))
            }
        }
        VM.skip(
            true,
            string.concat(
                rpcAlias, " RPC pruned block ", VM.toString(blockNumber), "; this pin needs an archive endpoint"
            )
        );
    }

    /// @dev True when `needle` occurs in `haystack`.
    function _contains(bytes memory haystack, bytes memory needle) private pure returns (bool) {
        if (needle.length > haystack.length) return false;
        for (uint256 i; i <= haystack.length - needle.length; ++i) {
            uint256 j;
            while (j < needle.length && haystack[i + j] == needle[j]) ++j;
            if (j == needle.length) return true;
        }
        return false;
    }

    /// @dev Minimal JSON-RPC hex quantity (`0x0`, `0x2a3f4e0`): nodes reject leading zero digits.
    function _toHexQuantity(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0x0";
        uint256 len;
        for (uint256 v = value; v != 0; v >>= 4) {
            ++len;
        }
        bytes memory out = new bytes(len + 2);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i = len + 1; i > 1; --i) {
            out[i] = bytes16("0123456789abcdef")[value & 0xf];
            value >>= 4;
        }
        return string(out);
    }
}
