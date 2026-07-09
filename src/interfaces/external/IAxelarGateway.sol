// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAxelarGateway
/// @author Vendored minimal subset of Axelar's GMP SDK
///         (https://github.com/axelarnetwork/axelar-gmp-sdk-solidity/blob/main/contracts/interfaces/IAxelarGateway.sol).
///         Upstream is MIT. Only the two methods the {AxelarGatewayAdapter} calls are re-declared.
///         Vendored subset — do not add an axelar-gmp-sdk dependency.
/// @notice The Axelar gateway: `callContract` emits an outgoing GMP message; `validateContractCall` is
///         called by the destination executable to authorize an inbound approved call.
interface IAxelarGateway {
    /// @notice Emit a cross-chain contract call to `contractAddress` on `destinationChain` with `payload`.
    function callContract(string calldata destinationChain, string calldata contractAddress, bytes calldata payload)
        external;

    /// @notice Validate (and consume) a gateway-approved inbound contract call. Returns true on first valid use.
    function validateContractCall(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash
    ) external returns (bool);
}
