// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IChainlinkCREAdapter
/// @author Modified from the Chainlink CRE consumer-contract guide
///         (https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts)
/// @notice Interface for the ChainlinkCREAdapter Diamond facet — a Chainlink CRE (Chainlink Runtime
///         Environment) workflow-report receiver.
/// @dev Push receiver (the inverse of the price adapters' pull model). The `KeystoneForwarder`
///      validates the DON's report signatures off-chain, then calls {onReport}, which is gated so that
///      (a) only the configured forwarder may call it and (b) only an admin-allowlisted workflow id may
///      write. The latest report per workflow is stored. Consumer facets that inherit
///      `ChainlinkCREAdapter` should override {onReport} (calling `super.onReport` first) to act on the
///      decoded report.
///
///      The module registers the canonical `type(IReceiver).interfaceId` for ERC-165 (so CRE tooling
///      detects the receiver), analogous to how the token modules register canonical ERC-721/ERC-1155
///      ids rather than their Lattice-specific interface ids.
interface IChainlinkCREAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the KeystoneForwarder is set.
    /// @param forwarder The forwarder allowed to call `onReport`.
    event CREForwarderSet(address forwarder);

    /// @notice Emitted when a workflow id's allowlist status changes.
    /// @param workflowId The CRE workflow id.
    /// @param allowed    True if the workflow may now write reports.
    event CREWorkflowSet(bytes32 indexed workflowId, bool allowed);

    /// @notice Emitted when a report is accepted and stored.
    /// @param workflowId    The CRE workflow id that produced the report.
    /// @param workflowOwner The workflow owner decoded from the metadata.
    /// @param reportId      The 2-byte report id decoded from the metadata.
    event ReportReceived(bytes32 indexed workflowId, address indexed workflowOwner, bytes2 reportId);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The forwarder has not been configured (forwarder address is zero).
    error CRENotConfigured();

    /// @notice `setForwarder` was called with the zero address.
    error CREInvalidForwarder();

    /// @notice `setWorkflow` was called with a zero workflow id.
    error CREInvalidWorkflowId();

    /// @notice `onReport` was called by an address other than the configured forwarder.
    /// @param caller The unauthorised caller.
    error CREOnlyForwarder(address caller);

    /// @notice `onReport` carried a workflow id that is not on the allowlist.
    /// @param workflowId The disallowed workflow id.
    error CREWorkflowNotAllowed(bytes32 workflowId);

    /// @notice `onReport` was called with metadata shorter than the required 64 bytes.
    error CREInvalidMetadata();

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the configured KeystoneForwarder.
    function getForwarder() external view returns (address);

    /// @notice Returns whether `workflowId` is allowed to write reports.
    /// @param workflowId The CRE workflow id.
    function isWorkflowAllowed(bytes32 workflowId) external view returns (bool);

    /// @notice Returns the latest report stored for `workflowId`.
    /// @param workflowId The CRE workflow id.
    /// @return report    The ABI-encoded report payload (empty if none stored).
    /// @return timestamp The block timestamp when the report was received (0 if none).
    function getLatestReport(bytes32 workflowId) external view returns (bytes memory report, uint256 timestamp);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Sets or replaces the KeystoneForwarder.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. Reverts `CREInvalidForwarder` on the zero address.
    /// @param forwarder The forwarder allowed to call `onReport`.
    function setForwarder(address forwarder) external;

    /// @notice Allows or disallows a workflow id from writing reports.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. Reverts `CREInvalidWorkflowId` on a zero id.
    /// @param workflowId The CRE workflow id.
    /// @param allowed    True to allow, false to disallow.
    function setWorkflow(bytes32 workflowId, bool allowed) external;

    // -------------------------------------------------------------------------
    //                                Operations
    // -------------------------------------------------------------------------

    /// @notice Called by the KeystoneForwarder to deliver a CRE workflow report.
    /// @dev Gated to the configured forwarder and to an allowlisted workflow id; decodes the metadata,
    ///      stores the latest report for that workflow, and emits `ReportReceived`. Consumer facets
    ///      should override this to consume the report.
    /// @param metadata Packed workflow identity (workflowId, workflowName, workflowOwner) + report id.
    /// @param report   The ABI-encoded workflow payload.
    function onReport(bytes calldata metadata, bytes calldata report) external;
}
