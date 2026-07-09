// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Origin} from "@lattice/interfaces/external/ILayerZeroEndpointV2.sol";

/// @title ILayerZeroReceiver (LayerZero v2) — vendored subset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal subset of LayerZero v2's `ILayerZeroReceiver` (https://github.com/LayerZero-Labs/LayerZero-v2). Upstream is MIT.
/// @notice Minimal vendored subset of the LayerZero v2 `ILayerZeroReceiver` — the destination-side interface an
///         OApp implements so the endpoint can deliver inbound messages via `lzReceive` and query the OApp's
///         nonce/path acceptance policy.
/// @dev Verified verbatim against `LayerZero-Labs/LayerZero-v2` (MIT):
///      `packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroReceiver.sol`. Re-declared at pragma
///      `^0.8.30` — do NOT add a `LayerZero-v2` dependency. Shares the {Origin} struct with {ILayerZeroEndpointV2}.
/// @custom:lattice-source LayerZero
interface ILayerZeroReceiver {
    /// @notice Returns whether the OApp accepts initialization of the messaging path from `_origin`.
    function allowInitializePath(Origin calldata _origin) external view returns (bool);

    /// @notice Returns the next expected inbound nonce for `(_eid, _sender)` (0 ⇒ unordered / no nonce enforced).
    function nextNonce(uint32 _eid, bytes32 _sender) external view returns (uint64);

    /// @notice Called by the endpoint to deliver an inbound message. `_executor` / `_extraData` are supplied by
    ///         the executor that triggered delivery.
    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable;
}
