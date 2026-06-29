// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC6900Validation
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Errors for the ERC-6900 ERC-4337 userOp validation (`ERC6900Validation` facet) and ERC-1271
///         signature validation (`ERC6900Signature` facet) paths. The applicability reverts
///         ({ValidationFunctionMissing}, {SelfCallRecursionDepthExceeded}, {UnrecognizedFunction}) are shared
///         with the executor and live on `IERC6900Executor`; the sparse-segment reverts live on
///         `SparseCalldataSegmentLib`.
/// @dev Re-implemented FRESH from the ERC-6900 reference semantics (erc6900/reference-implementation @ 65892c2).
interface IERC6900Validation {
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

    /// @notice The selected validation function is not flagged as a signature (ERC-1271) validation.
    error SignatureValidationInvalid(address module, uint32 entityId);
}
