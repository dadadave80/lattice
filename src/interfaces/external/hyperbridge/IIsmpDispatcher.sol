// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

/// @title IIsmpDispatcher
/// @author Vendored minimal subset of Hyperbridge's ismp-solidity
///         (https://github.com/polytope-labs/ismp-solidity). Upstream is Apache-2.0.
/// @notice Dispatch surface of the local Hyperbridge `IsmpHost` (upstream `IDispatcher`): POST-request
///         dispatch plus the two fee views the {HyperbridgeGatewayAdapter} quotes against. Hyperbridge is
///         PROOF-VERIFIED interop — consensus + state proofs are aggregated on a Polkadot-secured coprocessor
///         and delivered by permissionless proof-carrying relayers; there is NO attestation committee.
/// @dev Only the POST-request subset the adapter calls is re-declared (no GET requests, no responses, no
///      fundRequest) — do NOT add an ismp-solidity dependency. FEES: `dispatch` charges
///      `perByteFee(dest) * body.length + fee` in the ERC-20 {feeToken} to `msg.sender`; a native-token path
///      (the host swaps `msg.value` via its local uniswap router) exists upstream but is NOT used by the
///      adapter in v1.

/// @notice An object for dispatching POST requests to Hyperbridge.
struct DispatchPost {
    /// @notice Bytes representation of the destination state machine (e.g. `bytes("EVM-8453")`).
    bytes dest;
    /// @notice The destination module (the counterpart contract on `dest`).
    bytes to;
    /// @notice The request body.
    bytes body;
    /// @notice Timeout for this request in seconds (0 = no timeout — the host's default handling).
    uint64 timeout;
    /// @notice The amount put up to be paid to the relayer, charged in `feeToken` to `msg.sender`
    ///         (0 = unfunded/self-relay, valid in ISMP).
    uint256 fee;
    /// @notice Who pays for this request — the beneficiary of the host-side fee refund if it times out.
    address payer;
}

/// @notice A POST request as delivered/notified by the host to an `IIsmpModule`.
struct PostRequest {
    /// @notice The source state machine of this request.
    bytes source;
    /// @notice The destination state machine of this request.
    bytes dest;
    /// @notice The host-side protocol nonce (unique per source state machine).
    uint64 nonce;
    /// @notice Module Id of this request's origin (the trusted-remote auth material).
    bytes from;
    /// @notice Destination module id.
    bytes to;
    /// @notice Timestamp by which this request times out.
    uint64 timeoutTimestamp;
    /// @notice Request body.
    bytes body;
}

/// @notice An incoming POST request bundled with the relayer that delivered it.
struct IncomingPostRequest {
    /// @notice The POST request.
    PostRequest request;
    /// @notice Relayer responsible for delivering the request.
    address relayer;
}

/// @notice The ISMP dispatcher (implemented by the local `IsmpHost`).
interface IIsmpDispatcher {
    /// @notice The address of the ERC-20 fee token configured for this state machine. Hyperbridge collects
    ///         its dispatch fees in this denomination (typically a stablecoin). The host can migrate it —
    ///         integrators must read it LIVE, never cache it.
    function feeToken() external view returns (address);

    /// @notice The per-byte protocol fee configured for the destination state machine `dest`, charged in
    ///         {feeToken} for every byte of the outgoing request body.
    function perByteFee(bytes memory dest) external view returns (uint256);

    /// @notice Dispatches a POST request to Hyperbridge, charging `perByteFee(dest) * body.length +
    ///         request.fee` in {feeToken} to `msg.sender` (when no native value is supplied).
    /// @return commitment The request commitment (the host-side unique id of the request).
    function dispatch(DispatchPost memory request) external payable returns (bytes32 commitment);
}
