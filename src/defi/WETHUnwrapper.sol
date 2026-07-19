// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IWETH9} from "@lattice/interfaces/external/weth/IWETH9.sol";

/// @title WETHUnwrapper
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice WETH → ETH relay for diamond-hosted adapters. Canonical WETH9 pays `withdraw` via
///         `msg.sender.transfer` — a 2,300-gas stipend that cannot cover a diamond's zero-selector
///         routing to the {Receive} facet (cold selector-map `SLOAD` + delegatecall). An adapter
///         transfers its WETH here and calls {unwrap}: this contract absorbs the stipend send with a
///         plain `receive()` and returns the ETH to the caller with FULL gas (`call`), which the
///         diamond's {Receive} facet accepts.
/// @dev Stateless and permissionless. It holds funds only within the unwrap transaction — anything
///      parked here between transactions is claimable by the next `unwrap` caller, so ALWAYS
///      transfer-then-unwrap atomically. Deployed lazily per diamond via CREATE2 (see
///      `LidoAdapterLib._wethUnwrapper`).
contract WETHUnwrapper {
    /// @notice The full-gas ETH return to the caller failed.
    error WETHUnwrapper__EthReturnFailed();

    /// @notice Unwraps this contract's entire WETH balance and sends the ETH to the caller.
    /// @param _weth The WETH9 contract to withdraw from.
    function unwrap(IWETH9 _weth) external {
        _weth.withdraw(_weth.balanceOf(address(this)));
        (bool ok,) = msg.sender.call{value: address(this).balance}("");
        if (!ok) revert WETHUnwrapper__EthReturnFailed();
    }

    /// @notice Accepts WETH9's stipend-limited `transfer` payout.
    receive() external payable {}
}
