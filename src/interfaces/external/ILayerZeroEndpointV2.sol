// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ILayerZeroEndpointV2 (LayerZero v2 EndpointV2) — vendored subset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Minimal vendored subset of the LayerZero v2 `EndpointV2` (the OApp messaging endpoint): the `quote`
///         / `send` pair the adapter dispatches through, plus the `setDelegate` / `eid` / `lzToken` /
///         `nativeToken` reads. LayerZero routes by `uint32` endpoint id (eid), not EVM chainId.
/// @dev Verified verbatim against `LayerZero-Labs/LayerZero-v2` (MIT):
///      `packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroEndpointV2.sol` and its
///      `IMessageLibManager` / `IMessagingContext` message structs. Re-declared at pragma `^0.8.30` — do NOT
///      add a `LayerZero-v2` dependency. The shared message structs are file-level (see also
///      {ILayerZeroReceiver}, which imports {Origin} from here).
/// @custom:lattice-source LayerZero

/// @notice Parameters for an outbound message: destination eid, 32-byte receiver (the remote OApp), the
///         message body, the packed executor/DVN `options`, and whether the fee is paid in the LZ token.
struct MessagingParams {
    uint32 dstEid;
    bytes32 receiver;
    bytes message;
    bytes options;
    bool payInLzToken;
}

/// @notice Receipt returned by `send`: the message `guid`, its `nonce`, and the quoted `fee` charged.
struct MessagingReceipt {
    bytes32 guid;
    uint64 nonce;
    MessagingFee fee;
}

/// @notice The fee for a message, split into a native component and a LayerZero-token component.
struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

/// @notice The origin of an inbound message: the source eid, the 32-byte sender (remote OApp), and its nonce.
struct Origin {
    uint32 srcEid;
    bytes32 sender;
    uint64 nonce;
}

interface ILayerZeroEndpointV2 {
    /// @notice Quotes the messaging fee for `_params` as if sent by `_sender` (the OApp).
    function quote(MessagingParams calldata _params, address _sender) external view returns (MessagingFee memory);

    /// @notice Sends `_params`, refunding any unused native fee to `_refundAddress`. Returns the receipt.
    function send(MessagingParams calldata _params, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory);

    /// @notice Sets the OApp's delegate (the address permitted to configure the OApp's LayerZero libs/config).
    function setDelegate(address _delegate) external;

    /// @notice This endpoint's own endpoint id (eid).
    function eid() external view returns (uint32);

    /// @notice The LayerZero token used for the `lzTokenFee` (address(0) if unset).
    function lzToken() external view returns (address);

    /// @notice The native token used for the `nativeFee`.
    function nativeToken() external view returns (address);
}
