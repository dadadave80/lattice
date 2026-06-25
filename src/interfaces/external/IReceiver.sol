// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC165
/// @notice Minimal ERC-165 interface (vendored locally; the repo has no shared `IERC165`).
interface IERC165 {
    /// @notice Returns true if this contract implements the interface defined by `interfaceId`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @title IReceiver
/// @author Modified from Chainlink (https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/keystone/interfaces/IReceiver.sol)
/// @notice Consumer interface for receiving Chainlink CRE (Chainlink Runtime Environment) workflow
///         reports. The `KeystoneForwarder` validates the DON's report signatures off-chain, then calls
///         `onReport` on the consumer.
/// @dev Vendored — do not add a chainlink dependency. `type(IReceiver).interfaceId` is the canonical
///      CRE receiver id (the XOR of `onReport`'s selector only; the inherited `supportsInterface` is
///      excluded from a Solidity interface id), which is what CRE tooling queries via ERC-165.
interface IReceiver is IERC165 {
    /// @notice Called by the KeystoneForwarder to deliver a CRE workflow report.
    /// @param metadata Packed workflow identity: `abi.encodePacked(bytes32 workflowId,
    ///                 bytes10 workflowName, address workflowOwner)` (62 bytes) plus a trailing
    ///                 2-byte report id (64 bytes total).
    /// @param report   The ABI-encoded workflow payload (matches the workflow's `runtime.report()`).
    function onReport(bytes calldata metadata, bytes calldata report) external;
}
