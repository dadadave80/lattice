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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect AggregatorExecAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `execute(address,address,uint256,address,bytes)` 0x8e845c30
    ///      `isAllowedCall(address,bytes4)` 0x4cecd2a5
    ///      `setAllowedCall(address,bytes4,bool)` 0x2b370b67
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"8e845c304cecd2a52b370b67";
    }
}
