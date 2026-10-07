// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAccessManaged
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/manager/IAccessManaged.sol)
/// @notice Companion interface for contracts gated by an external AccessManager.
interface IAccessManaged {
    event AuthorityUpdated(address indexed newAuthority);

    error AccessManagedUnauthorized(address caller);
    error AccessManagedRequiredDelay(address caller, uint32 delay);
    error AccessManagedInvalidAuthority(address authority);

    function authority() external view returns (address);
    function setAuthority(address newAuthority) external;

    /// @notice Returns `isConsumingScheduledOp.selector` while this contract is consuming a scheduled operation
    ///         on its authority during a delayed direct call, and `0` otherwise.
    function isConsumingScheduledOp() external view returns (bytes4);
}
