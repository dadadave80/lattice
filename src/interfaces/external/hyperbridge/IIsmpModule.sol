// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.30;

import {IncomingPostRequest, PostRequest} from "@lattice/interfaces/external/hyperbridge/IIsmpDispatcher.sol";

/// @title IIsmpModule
/// @author Vendored minimal subset of Hyperbridge's ismp-solidity
///         (https://github.com/polytope-labs/ismp-solidity). Upstream is Apache-2.0.
/// @notice The six callbacks the local Hyperbridge `IsmpHost` invokes on a registered ISMP module. The
///         {HyperbridgeGatewayAdapter} implements ALL SIX (the host is the only authorized caller): `onAccept`
///         (inbound delivery) and `onPostRequestTimeout` (native timeout notification) are live paths; the
///         four response/GET hooks are never used by the adapter and revert.
/// @dev The shared POST structs live in {IIsmpDispatcher}; the response/GET structs below are re-declared only
///      as minimally as ABI fidelity requires (the hook selectors hash the full tuple types). `StorageValue`
///      is upstream's `@polytope-labs/solidity-merkle-trees/src/Types.sol` key/value pair. Do NOT add an
///      ismp-solidity dependency.

/// @notice A read storage key/value pair (from polytope-labs/solidity-merkle-trees `Types.sol`).
struct StorageValue {
    /// @notice The storage key.
    bytes key;
    /// @notice The storage value (may be empty when the key does not exist).
    bytes value;
}

/// @notice A POST response to a previously dispatched {PostRequest}.
struct PostResponse {
    /// @notice The request that initiated this response.
    PostRequest request;
    /// @notice Bytes for the POST response.
    bytes response;
    /// @notice Timestamp by which this response times out.
    uint64 timeoutTimestamp;
}

/// @notice A GET request for reading a counterparty state machine's storage.
struct GetRequest {
    /// @notice The source state machine of this request.
    bytes source;
    /// @notice The destination state machine of this request.
    bytes dest;
    /// @notice The host-side protocol nonce.
    uint64 nonce;
    /// @notice The origin module (an address on the source chain for GETs).
    address from;
    /// @notice Timestamp by which this request times out.
    uint64 timeoutTimestamp;
    /// @notice Storage keys to read.
    bytes[] keys;
    /// @notice Height at which to read the destination state machine.
    uint64 height;
    /// @notice Some application-specific metadata relating to this request.
    bytes context;
}

/// @notice A GET response carrying the requested storage values.
struct GetResponse {
    /// @notice The request that initiated this response.
    GetRequest request;
    /// @notice Storage values for the GET response.
    StorageValue[] values;
}

/// @notice An incoming POST response bundled with the relayer that delivered it.
struct IncomingPostResponse {
    /// @notice The POST response.
    PostResponse response;
    /// @notice Relayer responsible for delivering the response.
    address relayer;
}

/// @notice An incoming GET response bundled with the relayer that delivered it.
struct IncomingGetResponse {
    /// @notice The GET response.
    GetResponse response;
    /// @notice Relayer responsible for delivering the response.
    address relayer;
}

/// @notice The callbacks the `IsmpHost` invokes on a registered ISMP module.
interface IIsmpModule {
    /// @notice Called by the `IsmpHost` to notify the module of a new proof-verified POST request.
    function onAccept(IncomingPostRequest memory incoming) external;

    /// @notice Called by the `IsmpHost` to notify the module of a POST response to a previously sent request.
    function onPostResponse(IncomingPostResponse memory incoming) external;

    /// @notice Called by the `IsmpHost` to notify the module of a GET response to a previously sent request.
    function onGetResponse(IncomingGetResponse memory incoming) external;

    /// @notice Called by the `IsmpHost` to notify the module of a previously sent POST request that timed out.
    function onPostRequestTimeout(PostRequest memory request) external;

    /// @notice Called by the `IsmpHost` to notify the module of a previously sent POST response that timed out.
    function onPostResponseTimeout(PostResponse memory request) external;

    /// @notice Called by the `IsmpHost` to notify the module of a previously sent GET request that timed out.
    function onGetTimeout(GetRequest memory request) external;
}
