// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAccessManaged
/// @notice Companion interface for contracts gated by an external AccessManager.
interface IAccessManaged {
    event AuthorityUpdated(address indexed newAuthority);

    error AccessManagedUnauthorized(address caller);
    error AccessManagedRequiredDelay(address caller, uint32 delay);
    error AccessManagedInvalidAuthority(address authority);

    function authority() external view returns (address);
    function setAuthority(address newAuthority) external;
    function isConsumingScheduledOp() external view returns (bytes4);

    /// @notice Called by the AccessManager before and after an execute() call.
    ///         Setting `consuming` to `true` allows `restrictedCheck()` to bypass the
    ///         canCall gate for the duration of the manager-driven execution.
    /// @dev Only callable by the current authority.
    function setConsumingScheduledOp(bool consuming) external;
}
