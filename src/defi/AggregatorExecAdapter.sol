// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AggregatorExecAdapterLib} from "@lattice/defi/libraries/AggregatorExecAdapterLib.sol";
import {IAggregatorExecAdapter} from "@lattice/interfaces/defi/IAggregatorExecAdapter.sol";

/// @title AggregatorExecAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from LI.FI (https://github.com/lifinance/contracts)
/// @notice Generic swap/bridge EXECUTION facet: forwards user-supplied, off-chain-built calldata to an
///         admin-ALLOW-LISTED `(aggregator, selector)` pair (the LI.FI Diamond is the canonical first
///         aggregator). The MOST security-sensitive adapter in the suite — it makes an ARBITRARY external call
///         from a fund-holding diamond, so the whole design is confused-deputy prevention. NOT an ERC-7786 gateway.
/// @dev Stateless delegator — logic/storage live in {AggregatorExecAdapterLib}. {execute} is `nonReentrant` with
///      strict CEI: funds come only from `msg.sender`, the aggregator gets an EXACT, immediately-reset approval,
///      and every leftover (unspent input, output delta, unspent native) is swept back to the caller.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source LI.FI
contract AggregatorExecAdapter is IAggregatorExecAdapter {
    /// @inheritdoc IAggregatorExecAdapter
    function setAllowedCall(address aggregator, bytes4 selector, bool allowed) external virtual {
        AggregatorExecAdapterLib.setAllowedCall(aggregator, selector, allowed);
    }

    /// @inheritdoc IAggregatorExecAdapter
    function isAllowedCall(address aggregator, bytes4 selector) external view virtual returns (bool) {
        return AggregatorExecAdapterLib.isAllowedCall(aggregator, selector);
    }

    /// @inheritdoc IAggregatorExecAdapter
    function execute(
        address aggregator,
        address inputToken,
        uint256 amount,
        address outputToken,
        bytes calldata callData
    ) external payable virtual returns (bytes memory ret) {
        return AggregatorExecAdapterLib.execute(aggregator, inputToken, amount, outputToken, callData);
    }
}
