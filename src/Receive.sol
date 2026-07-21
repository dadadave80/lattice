// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Receive
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Bare-ETH acceptance as a facet: cut this under the ZERO selector (`bytes4(0)`) and the
///         diamond accepts plain ETH sends. An empty-calldata call reads as `msg.sig == 0x00000000`
///         in the diamond's fallback, routes to this facet, and the empty-calldata delegatecall runs
///         this contract's `receive()` in the diamond's context. Every Lattice recipe cuts it —
///         {Lattice} itself deliberately declares NO `receive()`, so a diamond without this
///         facet rejects bare ETH (an explicit opt-out for contracts that should never hold value).
/// @dev Stateless, no init, no interface, no ERC-165 registration (there is nothing to register —
///      `receive()` has no selector). Only genuinely EMPTY calldata succeeds: 1-4 zero bytes still
///      route here via the zero-padded `msg.sig` but match no function and revert. NOTE the routing
///      costs a cold selector-map `SLOAD` + delegatecall (~4,700 gas), so Solidity `.transfer()` /
///      `.send()` with their 2,300-gas stipend CANNOT pay a Lattice diamond — senders must use
///      `call{value: ...}("")`.
contract Receive {
    /// @notice Accept bare ETH (vault deposits, account funding, timelock/governor value).
    receive() external payable virtual {}

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev The single export is the ZERO selector `0x00000000` — the empty-calldata `msg.sig` the
    ///      diamond fallback looks up. `receive()` has no selector of its own, so this is the ONE
    ///      facet whose export deliberately diverges from `forge inspect` methodIdentifiers
    ///      (ExportSelectorsParityTest carries the documented special case). Excludes
    ///      `exportSelectors()` itself (0x0ef22643) — it is never cut into a diamond.
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"00000000";
    }
}
