// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC7821Executor
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Error/event surface of the `ERC7821Executor` facet. The `execute` / `supportsExecutionMode`
///         entrypoints are on the vendored `IERC7821`.
/// @dev Authorizes `execute` for: the account itself (`address(this)`), the configured ERC-4337 EntryPoint,
///      a `DEFAULT_ADMIN_ROLE` holder, or — for the opData mode — an owner-signed EIP-712 `Execute` envelope
///      relayed by anyone (nonce-protected).
interface IERC7821Executor {
    /// @notice Emitted once per `execute` batch, after all calls succeed.
    event BatchExecuted(bytes32 indexed mode, uint256 calls);

    /// @notice The caller is not authorized to execute a batch.
    error UnauthorizedExecutor(address caller);

    /// @notice The requested execution `mode` is not supported.
    error UnsupportedExecutionMode(bytes32 mode);
}
