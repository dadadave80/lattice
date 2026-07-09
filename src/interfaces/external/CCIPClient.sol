// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Client (Chainlink CCIP) — vendored subset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal subset of Chainlink CCIP's `Client` library (https://github.com/smartcontractkit/chainlink-ccip). Upstream is MIT.
/// @notice Minimal vendored subset of Chainlink CCIP's `Client` library: the EVM messaging structs and the
///         `GenericExtraArgsV2` encoder used by {CCIPGatewayAdapter}. Per the repo "vendor, don't install"
///         policy, only the surface this Diamond uses is copied — not the SVM/Sui/legacy types.
/// @dev Verified verbatim against `smartcontractkit/chainlink-ccip` @ `main` commit `828897a` (2026-06-24):
///      `chains/evm/contracts/libraries/Client.sol`. `extraArgs` is `tag || abi.encode(struct)` — never a
///      bare `abi.encode`. Empty `extraArgs` defaults to a 200k destination gas limit upstream.
/// @custom:lattice-source Chainlink
library Client {
    /// @notice A token + amount pair carried by a CCIP message.
    struct EVMTokenAmount {
        address token;
        uint256 amount;
    }

    /// @notice The message shape delivered to an `IAny2EVMMessageReceiver` on the destination chain.
    struct Any2EVMMessage {
        bytes32 messageId;
        uint64 sourceChainSelector;
        bytes sender;
        bytes data;
        EVMTokenAmount[] destTokenAmounts;
    }

    /// @notice The message shape submitted to `IRouterClient.ccipSend` on the source chain.
    struct EVM2AnyMessage {
        bytes receiver;
        bytes data;
        EVMTokenAmount[] tokenAmounts;
        address feeToken;
        bytes extraArgs;
    }

    /// @dev `bytes4(keccak256("CCIP EVMExtraArgsV2"))`; the multi-chain-family default extra-args selector.
    bytes4 public constant GENERIC_EXTRA_ARGS_V2_TAG = 0x181dcf10;

    /// @notice Generic (V2) extra args for EVM destinations.
    /// @dev `allowOutOfOrderExecution` is enforced on some lanes (wrong value reverts) — keep it configurable.
    struct GenericExtraArgsV2 {
        uint256 gasLimit;
        bool allowOutOfOrderExecution;
    }

    /// @notice ABI-encodes `GenericExtraArgsV2` with its tag selector for the `extraArgs` field.
    function _argsToBytes(GenericExtraArgsV2 memory extraArgs) internal pure returns (bytes memory bts) {
        return abi.encodeWithSelector(GENERIC_EXTRA_ARGS_V2_TAG, extraArgs);
    }
}
