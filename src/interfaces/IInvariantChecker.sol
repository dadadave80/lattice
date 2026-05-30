// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IInvariantChecker
/// @notice Interface for the InvariantChecker module — a registry of named invariants
///         (bytes32 → target + selector) that can be checked on-chain via `staticcall`.
interface IInvariantChecker {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @dev Emitted when an invariant is registered or updated.
    /// @param key      The invariant key.
    /// @param target   The contract address to call.
    /// @param selector The function selector to invoke (must return bool).
    event InvariantRegistered(bytes32 indexed key, address target, bytes4 selector);

    /// @dev Emitted when an invariant is unregistered.
    /// @param key The invariant key that was removed.
    event InvariantUnregistered(bytes32 indexed key);

    /// @dev Emitted when an invariant check returns false.
    /// @param key        The invariant key that was violated.
    /// @param returnData The raw return data from the staticcall.
    event InvariantViolated(bytes32 indexed key, bytes returnData);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @dev Thrown when `checkInvariant` is called for a key that has not been registered.
    /// @param key The unregistered invariant key.
    error InvariantNotRegistered(bytes32 key);

    /// @dev Thrown when the staticcall returns `false`, indicating an invariant violation.
    /// @param key The invariant key whose check returned false.
    error InvariantViolatedError(bytes32 key);

    /// @dev Thrown when the staticcall itself reverts (e.g., invalid target, out-of-gas).
    /// @param key The invariant key whose staticcall failed.
    error InvariantCheckFailed(bytes32 key);

    /// @dev Thrown when `registerInvariant` is called with `target == address(0)`.
    error InvariantInvalidTarget();

    // -------------------------------------------------------------------------
    // View functions
    // -------------------------------------------------------------------------

    /// @notice Returns the target address and function selector registered for `key`.
    /// @param key The invariant key to query.
    /// @return target   The contract address to call.
    /// @return selector The function selector to invoke.
    function getInvariant(bytes32 key) external view returns (address target, bytes4 selector);

    /// @notice Performs the staticcall check for `key` and reverts on violation or call failure.
    /// @dev Reverts with `InvariantNotRegistered` if the key is unregistered.
    ///      Reverts with `InvariantViolatedError` if the call returns false.
    ///      Reverts with `InvariantCheckFailed` if the staticcall reverts.
    /// @param key The invariant key to check.
    function checkInvariant(bytes32 key) external view;

    /// @notice Checks multiple invariants in order, reverting on the first failure.
    /// @param keys The array of invariant keys to check sequentially.
    function checkInvariants(bytes32[] calldata keys) external view;

    // -------------------------------------------------------------------------
    // State-changing functions
    // -------------------------------------------------------------------------

    /// @notice Registers or updates an invariant.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Reverts if `target == address(0)`.
    ///      Emits `InvariantRegistered`.
    /// @param key      The invariant key.
    /// @param target   The contract address to call (must not be address(0)).
    /// @param selector The function selector to invoke (must return a bool).
    function registerInvariant(bytes32 key, address target, bytes4 selector) external;

    /// @notice Removes a registered invariant.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Emits `InvariantUnregistered`.
    /// @param key The invariant key to remove.
    function unregisterInvariant(bytes32 key) external;
}
