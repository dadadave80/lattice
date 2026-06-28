// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IValidation6900
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Errors for the ERC-6900 ERC-4337 userOp validation path (`ERC6900Validation` facet). The applicability
///         reverts ({ValidationFunctionMissing}, {SelfCallRecursionDepthExceeded}, {UnrecognizedFunction}) are
///         shared with the executor and live on `IExecutor6900`; the sparse-segment reverts live on
///         `SparseCalldataSegmentLib`.
/// @dev Re-implemented FRESH from the ERC-6900 reference semantics (erc6900/reference-implementation @ 65892c2).
interface IValidation6900 {
    /// @notice `validateUserOp` was called by an address other than the configured EntryPoint.
    error NotFromEntryPoint(address caller);

    /// @notice The selected validation function is not flagged as a user-op validation (`isUserOpValidation`).
    error UserOpValidationInvalid(address module, uint32 entityId);

    /// @notice A pre-userOp-validation hook returned an authorizer other than 0 (success) or 1 (failure) — hooks
    ///         may not delegate to a signature aggregator.
    error UnexpectedAggregator(address module, uint32 entityId, address aggregator);

    /// @notice The selected validation has execution hooks, which require the `executeUserOp` wrapper to run at
    ///         execution time (not yet supported); the userOp is rejected rather than silently skipping them.
    error RequireUserOperationContext();
}
