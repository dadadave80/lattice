// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4;

/// @title IWormholeRelayer / IWormholeReceiver
/// @author Vendored minimal subset of the Wormhole Solidity SDK
///         (https://github.com/wormhole-foundation/wormhole-solidity-sdk). Upstream is Apache-2.0.
///         Only the methods the {WormholeGatewayAdapter} calls/implements are re-declared.
///         Vendored subset — do not add a wormhole-solidity-sdk dependency.
/// @notice `IWormholeRelayer` is the standard relayer (send + quote); `IWormholeReceiver` is the callback
///         the relayer invokes on delivery. Addresses are Wormhole "universal" 32-byte addresses.
interface IWormholeRelayer {
    /// @notice Request delivery of `payload` to `targetAddress` on `targetChain` (Wormhole chain id).
    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes calldata payload,
        uint256 receiverValue,
        uint256 gasLimit,
        uint16 refundChain,
        address refundAddress
    ) external payable returns (uint64 sequence);

    /// @notice Quote the native cost of an EVM delivery with `gasLimit` + `receiverValue` to `targetChain`.
    function quoteEVMDeliveryPrice(uint16 targetChain, uint256 receiverValue, uint256 gasLimit)
        external
        view
        returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused);
}

interface IWormholeReceiver {
    /// @notice Delivery callback invoked by the Wormhole relayer. `sourceAddress` is a universal address.
    function receiveWormholeMessages(
        bytes calldata payload,
        bytes[] calldata additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable;
}
