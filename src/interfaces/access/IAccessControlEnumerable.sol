// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";

/// @title IAccessControlEnumerable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/extensions/IAccessControlEnumerable.sol)
/// @notice Extends IAccessControl with role-member enumeration.
interface IAccessControlEnumerable is IAccessControl {
    /// @notice Returns the `index`-th address holding `role`.
    /// @dev Reverts (Solidity array OOB) if `index >= getRoleMemberCount(role)`.
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);

    /// @notice Returns the number of addresses holding `role`.
    function getRoleMemberCount(bytes32 role) external view returns (uint256);

    /// @notice Returns all addresses holding `role`. Gas-heavy for large sets.
    function getRoleMembers(bytes32 role) external view returns (address[] memory);
}
