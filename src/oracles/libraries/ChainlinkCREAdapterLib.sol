// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IChainlinkCREAdapter} from "@lattice/interfaces/IChainlinkCREAdapter.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ChainlinkCREAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CHAINLINK_CRE_ADAPTER_STORAGE_SLOT =
    0x38811f86f85f0447c0970d57466dc7a3c4187640f04a44e7622c183e45f90b00;

/// @dev 0x805f2132 is the canonical `type(IReceiver).interfaceId` (the XOR of `onReport`'s selector
///      only; the inherited `supportsInterface` is excluded). The module registers this canonical CRE
///      receiver id — rather than the Lattice `type(IChainlinkCREAdapter).interfaceId` — so CRE tooling
///      detects the receiver via ERC-165, mirroring the ERC-721/ERC-1155 canonical-id precedent.
/// `keccak256(abi.encode(bytes4(0x805f2132), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IRECEIVER_SLOT = 0x441e497903b68a1fc13e526fe3469e615b027289cdd3d767c8ce4993ccc4bf83;

/// @notice A stored CRE workflow report.
struct CREReport {
    bytes data;
    uint256 timestamp;
}

/// @notice ERC-7201 namespaced storage for ChainlinkCREAdapter.
/// @custom:storage-location erc7201:lattice.storage.ChainlinkCREAdapter
struct ChainlinkCREAdapterStorage {
    address _forwarder;
    mapping(bytes32 workflowId => bool allowed) _workflows;
    mapping(bytes32 workflowId => CREReport report) _latestReports;
}

/// @title ChainlinkCREAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from the Chainlink CRE consumer-contract guide
///         (https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts)
/// @notice Library implementing a Chainlink CRE (Chainlink Runtime Environment) workflow-report
///         receiver. The `KeystoneForwarder` validates the DON's report signatures off-chain, then
///         calls `onReport`, which is gated to the configured forwarder AND to an admin-allowlisted
///         workflow id. The latest report per workflow is stored; consumer facets inheriting
///         `ChainlinkCREAdapter` should override `onReport` (calling `super.onReport` first) to act on
///         the decoded report.
/// @dev IMPLEMENTATION NOTE — this follows the guide's "Direct IReceiver Implementation" path, NOT its
///      `ReceiverTemplate` base contract. `ReceiverTemplate` is an `Ownable`, constructor-initialized
///      standalone contract (`constructor(address forwarder) Ownable(msg.sender)`) and is structurally
///      incompatible with a Lattice Diamond facet, which is stateless (initialized via
///      `__ChainlinkCREAdapter_init`, no constructor), keeps state in ERC-7201 namespaced storage, gates
///      on `AccessControl` roles (`DEFAULT_ADMIN_ROLE`) rather than `Ownable`, and registers ERC-165
///      through the shared diamond `ERC165Lib` map. Each `ReceiverTemplate` feature is re-created here,
///      adapted to that model: its `onlyForwarder` modifier -> the `msg.sender == forwarder` check; its
///      constructor forwarder + `setForwarderAddress` -> `setForwarder`; its optional
///      `setExpectedWorkflowId` validation -> the mandatory `setWorkflow` allowlist (the workflow id
///      already binds owner + name + workflow binary, so per-field owner/name checks are unnecessary);
///      its `_decodeMetadata` helper -> `_decodeMetadata` here; and its abstract
///      `_processReport(bytes)` hook -> the stored latest report plus the `virtual onReport` that
///      consumer facets override (the same callback pattern as the other Lattice adapters). There is
///      therefore intentionally no `_processReport` function in this module.
library ChainlinkCREAdapterLib {
    /// @dev The KeystoneForwarder always delivers 64-byte metadata: 62 packed bytes
    ///      (workflowId ++ workflowName ++ workflowOwner) plus a trailing 2-byte report id.
    uint256 private constant _METADATA_LENGTH = 64;

    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ERC-7201 storage struct for ChainlinkCREAdapter.
    function chainlinkCREAdapterStorage() internal pure returns (ChainlinkCREAdapterStorage storage $) {
        assembly {
            $.slot := CHAINLINK_CRE_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the canonical IReceiver ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __ChainlinkCREAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for the canonical IReceiver id.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IRECEIVER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the configured KeystoneForwarder.
    function getForwarder() internal view returns (address) {
        return chainlinkCREAdapterStorage()._forwarder;
    }

    /// @notice Returns whether `workflowId` is allowed to write reports.
    /// @param workflowId The CRE workflow id.
    function isWorkflowAllowed(bytes32 workflowId) internal view returns (bool) {
        return chainlinkCREAdapterStorage()._workflows[workflowId];
    }

    /// @notice Returns the latest report stored for `workflowId`.
    /// @param workflowId The CRE workflow id.
    /// @return report    The ABI-encoded report payload (empty if none stored).
    /// @return timestamp The block timestamp when the report was received (0 if none).
    function getLatestReport(bytes32 workflowId) internal view returns (bytes memory report, uint256 timestamp) {
        CREReport storage r = chainlinkCREAdapterStorage()._latestReports[workflowId];
        report = r.data;
        timestamp = r.timestamp;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets or replaces the KeystoneForwarder.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE. Reverts `CREInvalidForwarder` on the zero address.
    /// @param forwarder The forwarder allowed to call `onReport`.
    function setForwarder(address forwarder) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (forwarder == address(0)) revert IChainlinkCREAdapter.CREInvalidForwarder();
        chainlinkCREAdapterStorage()._forwarder = forwarder;
        emit IChainlinkCREAdapter.CREForwarderSet(forwarder);
    }

    /// @notice Allows or disallows a workflow id from writing reports.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE. Reverts `CREInvalidWorkflowId` on a zero id.
    /// @param workflowId The CRE workflow id.
    /// @param allowed    True to allow, false to disallow.
    function setWorkflow(bytes32 workflowId, bool allowed) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (workflowId == bytes32(0)) revert IChainlinkCREAdapter.CREInvalidWorkflowId();
        chainlinkCREAdapterStorage()._workflows[workflowId] = allowed;
        emit IChainlinkCREAdapter.CREWorkflowSet(workflowId, allowed);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Called by the KeystoneForwarder to deliver a CRE workflow report.
    /// @dev Authenticates the forwarder by its address (`msg.sender`), decodes the packed metadata,
    ///      checks the workflow id against the allowlist, stores the latest report, and emits
    ///      `ReportReceived`.
    ///
    ///      NOTE: This function only manages bookkeeping. Consumer facets that inherit
    ///      `ChainlinkCREAdapter` should override `onReport` (calling `super.onReport` first) to act on
    ///      the delivered report.
    /// @param metadata Packed workflow identity (workflowId, workflowName, workflowOwner) + report id.
    /// @param report   The ABI-encoded workflow payload.
    function onReport(bytes calldata metadata, bytes calldata report) internal {
        ChainlinkCREAdapterStorage storage $ = chainlinkCREAdapterStorage();

        address forwarder = $._forwarder;
        if (forwarder == address(0)) revert IChainlinkCREAdapter.CRENotConfigured();
        if (msg.sender != forwarder) revert IChainlinkCREAdapter.CREOnlyForwarder(msg.sender);
        if (metadata.length < _METADATA_LENGTH) revert IChainlinkCREAdapter.CREInvalidMetadata();

        (bytes32 workflowId, address workflowOwner, bytes2 reportId) = _decodeMetadata(metadata);
        if (!$._workflows[workflowId]) revert IChainlinkCREAdapter.CREWorkflowNotAllowed(workflowId);

        CREReport storage r = $._latestReports[workflowId];
        r.data = report;
        r.timestamp = block.timestamp;

        emit IChainlinkCREAdapter.ReportReceived(workflowId, workflowOwner, reportId);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Decodes the KeystoneForwarder metadata, packed as
    ///         `abi.encodePacked(bytes32 workflowId, bytes10 workflowName, address workflowOwner)` with
    ///         a trailing 2-byte report id.
    /// @dev Caller must ensure `metadata.length >= 64`. `workflowName` is intentionally not returned.
    function _decodeMetadata(bytes calldata metadata)
        private
        pure
        returns (bytes32 workflowId, address workflowOwner, bytes2 reportId)
    {
        assembly ("memory-safe") {
            workflowId := calldataload(metadata.offset)
            // workflowOwner occupies bytes [42, 62): the high 20 bytes of the word at offset 42.
            workflowOwner := shr(96, calldataload(add(metadata.offset, 42)))
            // reportId occupies bytes [62, 64): the high 2 bytes of the word at offset 62.
            reportId := and(calldataload(add(metadata.offset, 62)), shl(240, 0xffff))
        }
    }
}
