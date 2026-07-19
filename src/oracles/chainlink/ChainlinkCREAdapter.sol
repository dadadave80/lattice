// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IChainlinkCREAdapter} from "@lattice/interfaces/oracles/IChainlinkCREAdapter.sol";
import {ChainlinkCREAdapterLib} from "@lattice/oracles/libraries/ChainlinkCREAdapterLib.sol";

/// @title ChainlinkCREAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from the Chainlink CRE consumer-contract guide
///         (https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts)
/// @notice Diamond facet that receives Chainlink CRE (Chainlink Runtime Environment) workflow reports
///         via the `IReceiver.onReport` entry point, delivered by the KeystoneForwarder.
/// @dev Stateless delegator — all logic and storage live in ChainlinkCREAdapterLib.
///
///      `onReport` is gated to the configured forwarder and an admin-allowlisted workflow id, then
///      stores the latest report per workflow. Consumer facets that inherit this contract should
///      override `onReport` to act on the delivered report after calling `super.onReport`.
///
///      The module registers the canonical `type(IReceiver).interfaceId` for ERC-165 so CRE tooling
///      detects the receiver (the ERC-721/ERC-1155 canonical-id precedent).
///
///      This follows the guide's "Direct IReceiver Implementation" path, not the `Ownable`/
///      constructor-based `ReceiverTemplate` (incompatible with the stateless facet + ERC-7201 model);
///      the `virtual onReport` override is the Lattice analogue of `ReceiverTemplate._processReport`.
///      See `ChainlinkCREAdapterLib` for the full mapping.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Chainlink
contract ChainlinkCREAdapter is IChainlinkCREAdapter {
    /// @inheritdoc IChainlinkCREAdapter
    function getForwarder() external view virtual override returns (address) {
        return ChainlinkCREAdapterLib.getForwarder();
    }

    /// @inheritdoc IChainlinkCREAdapter
    function isWorkflowAllowed(bytes32 workflowId) external view virtual override returns (bool) {
        return ChainlinkCREAdapterLib.isWorkflowAllowed(workflowId);
    }

    /// @inheritdoc IChainlinkCREAdapter
    function getLatestReport(bytes32 workflowId)
        external
        view
        virtual
        override
        returns (bytes memory report, uint256 timestamp)
    {
        return ChainlinkCREAdapterLib.getLatestReport(workflowId);
    }

    /// @inheritdoc IChainlinkCREAdapter
    function setForwarder(address forwarder) external virtual override {
        ChainlinkCREAdapterLib.setForwarder(forwarder);
    }

    /// @inheritdoc IChainlinkCREAdapter
    function setWorkflow(bytes32 workflowId, bool allowed) external virtual override {
        ChainlinkCREAdapterLib.setWorkflow(workflowId, allowed);
    }

    /// @inheritdoc IChainlinkCREAdapter
    function onReport(bytes calldata metadata, bytes calldata report) external virtual override {
        ChainlinkCREAdapterLib.onReport(metadata, report);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ChainlinkCREAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `getForwarder()` 0xa0042526
    ///      `getLatestReport(bytes32)` 0x4def3188
    ///      `isWorkflowAllowed(bytes32)` 0xe35f6eba
    ///      `onReport(bytes,bytes)` 0x805f2132
    ///      `setForwarder(address)` 0xb9998a24
    ///      `setWorkflow(bytes32,bool)` 0x2a93711e
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"a00425264def3188e35f6eba805f2132b9998a242a93711e";
    }
}
