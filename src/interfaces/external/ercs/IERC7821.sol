// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC7821 — Minimal batch executor
/// @author Re-authored to the ERC-7821 standard ABI (reference: Vectorized/solady `src/accounts/ERC7821.sol`,
///         MIT; OpenZeppelin `draft-ERC7821`). Vendored subset — do not add an external dependency.
/// @notice ERC-7821 single entrypoint for executing a batch of calls. The `mode` selects the encoding of
///         `executionData`; capability is discovered via {supportsExecutionMode} (ERC-7821 defines NO ERC-165
///         interface id).
/// @dev Supported `mode` ids (10-byte prefix, rest zero):
///      - `0x01000000000000000000` — single batch: `executionData = abi.encode(Call[])`.
///      - `0x01000000000078210001` — single batch + opData: `executionData = abi.encode(Call[], bytes opData)`.
///      The `0x7821...0001` infix marks the ERC-7821 "opData" variant.

/// @dev One call in a batch. `data` empty + `value` set is a plain ETH transfer to `target`.
struct Call {
    address target;
    uint256 value;
    bytes data;
}

interface IERC7821 {
    /// @notice Executes a batch of calls encoded per `mode`.
    /// @dev Authorization is implementation-defined (this account: self / EntryPoint / admin / signed opData).
    /// @param mode The execution mode selecting the `executionData` encoding.
    /// @param executionData The encoded calls (and optional opData), per `mode`.
    function execute(bytes32 mode, bytes calldata executionData) external payable;

    /// @notice Whether `mode` is supported by {execute}.
    /// @param mode The execution mode to query.
    /// @return result True if supported.
    function supportsExecutionMode(bytes32 mode) external view returns (bool result);
}
