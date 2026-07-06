// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC6900Executor
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-6900 reference implementation (https://github.com/erc6900/reference-implementation)
/// @notice Errors for the ERC-6900 runtime executor + dispatch pipeline (`ERC6900Executor` facet /
///         `ModularAccount6900` fallback). The execution + config functions live on the vendored
///         `IERC6900Account`; these cover the runtime dispatch / validation / hook failure modes.
/// @dev Re-implemented FRESH from the ERC-6900 reference semantics (erc6900/reference-implementation @ 65892c2).
interface IERC6900Executor {
    /// @notice No installed execution module owns `selector` (and it is not a facet selector).
    error UnrecognizedFunction(bytes4 selector);

    /// @notice The chosen (or implicit direct-call) validation function may not validate `selector` — it is
    ///         neither a permitted global validation for the selector nor in the validation's selector set.
    error ValidationFunctionMissing(bytes4 selector);

    /// @notice A validated `execute`/`executeBatch` re-entered `execute`/`executeBatch` on this account (self-call
    ///         recursion is capped at one level).
    error SelfCallRecursionDepthExceeded();

    /// @notice A pre-execution hook reverted; the module's revert data is forwarded in `revertReason`.
    error PreExecHookReverted(address module, uint32 entityId, bytes revertReason);

    /// @notice A post-execution hook reverted.
    error PostExecHookReverted(address module, uint32 entityId, bytes revertReason);

    /// @notice A pre-runtime-validation hook reverted.
    error PreRuntimeValidationHookFailed(address module, uint32 entityId, bytes revertReason);

    /// @notice A runtime validation function (`validateRuntime`) reverted.
    error RuntimeValidationFunctionReverted(address module, uint32 entityId, bytes revertReason);
}
