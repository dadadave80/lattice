// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title INonces
/// @notice Interface for tracking per-account nonces used in replay-protection schemes.
interface INonces {
    /// @dev Thrown when an account nonce is used with an incorrect expected value.
    /// @param account The account whose nonce was checked.
    /// @param currentNonce The current (correct) nonce for the account.
    error InvalidAccountNonce(address account, uint256 currentNonce);

    /// @notice Returns the current nonce for the given owner.
    /// @param owner The address to query.
    /// @return The current nonce.
    function nonces(address owner) external view returns (uint256);
}
