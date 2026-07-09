// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ISafe
/// @author Modified from Safe (https://github.com/safe-global/safe-smart-account/blob/main/contracts/Safe.sol)
/// @notice Minimal vendored subset of the Gnosis Safe smart-contract multisig surface used to validate
///         and introspect a pinned Safe authority.
/// @dev A Safe collects M-of-N owner signatures OFF-CHAIN and verifies the threshold ON-CHAIN inside
///      `execTransaction`, then dispatches the inner call to the target (here, the Diamond). When the
///      Safe executes with `operation = Call` (the REQUIRED mode — never DelegateCall), the Diamond sees
///      `msg.sender == theSafe`. The Lattice cut facets therefore do NOT re-verify any signatures; they
///      trust solely that `msg.sender == the pinned Safe address`. Only the read-only views needed to
///      sanity-check that a pinned address is a real, sensibly-configured Safe are declared here.
interface ISafe {
    /// @notice Returns the number of owner signatures required to execute a Safe transaction.
    /// @dev Used at init to assert the pinned Safe enforces a sane minimum threshold (M-of-N).
    /// @return The current signature threshold.
    function getThreshold() external view returns (uint256);

    /// @notice Returns the full list of Safe owners.
    /// @return The array of owner addresses.
    function getOwners() external view returns (address[] memory);

    /// @notice Returns whether `owner` is an owner of the Safe.
    /// @param owner The address to query.
    /// @return `true` if `owner` is a Safe owner.
    function isOwner(address owner) external view returns (bool);

    /// @notice Returns the Safe's current transaction nonce.
    /// @return The current nonce.
    function nonce() external view returns (uint256);
}
