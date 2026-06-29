// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC4337Validation
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Admin/read surface of the `ERC4337Validation` facet. `validateUserOp` itself is on the vendored
///         `IAccount` (ERC-4337). This is the Diamond-local config: which EntryPoint is trusted.
/// @dev The EntryPoint is stored, never hardcoded, so the canonical version (v0.7/v0.8/v0.9) is a deploy
///      choice. Signature validation is delegated to the configured ECDSA signer (`AccountSigner`).
interface IERC4337Validation {
    /// @notice Emitted when the trusted EntryPoint is set.
    event EntryPointSet(address indexed entryPoint);

    /// @notice `validateUserOp` was called by an address other than the configured EntryPoint.
    error NotFromEntryPoint(address caller);

    /// @notice The EntryPoint address is the zero address.
    error InvalidEntryPoint();

    /// @notice The ERC-4337 EntryPoint trusted to call `validateUserOp`.
    function entryPoint() external view returns (address);

    /// @notice Sets the trusted EntryPoint. Admin only.
    function setEntryPoint(address entryPoint) external;
}
