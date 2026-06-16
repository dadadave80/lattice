// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAccessManager
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/manager/IAccessManager.sol)
/// @notice Centralized authority: roles, hierarchies, grant/execution delays,
///         per-target function-selector permissions, operation scheduling.
///         Mirrors OpenZeppelin v5 AccessManager.
interface IAccessManager {
    // ---- Events ----

    event OperationScheduled(
        bytes32 indexed operationId, uint32 indexed nonce, uint48 schedule, address caller, address target, bytes data
    );
    event OperationExecuted(bytes32 indexed operationId, uint32 indexed nonce);
    event OperationCanceled(bytes32 indexed operationId, uint32 indexed nonce);
    event RoleLabel(uint64 indexed roleId, string label);
    event RoleGranted(uint64 indexed roleId, address indexed account, uint32 delay, uint48 since, bool newMember);
    event RoleRevoked(uint64 indexed roleId, address indexed account);
    event RoleAdminChanged(uint64 indexed roleId, uint64 indexed admin);
    event RoleGuardianChanged(uint64 indexed roleId, uint64 indexed guardian);
    event RoleGrantDelayChanged(uint64 indexed roleId, uint32 delay, uint48 since);
    event TargetClosed(address indexed target, bool closed);
    event TargetFunctionRoleUpdated(address indexed target, bytes4 selector, uint64 indexed roleId);
    event TargetAdminDelayUpdated(address indexed target, uint32 delay, uint48 since);

    // ---- Errors ----

    error AccessManagerAlreadyScheduled(bytes32 operationId);
    error AccessManagerNotScheduled(bytes32 operationId);
    error AccessManagerNotReady(bytes32 operationId);
    error AccessManagerExpired(bytes32 operationId);
    error AccessManagerLockedRole(uint64 roleId);
    error AccessManagerBadConfirmation();
    error AccessManagerUnauthorizedAccount(address caller, uint64 roleId);
    error AccessManagerUnauthorizedConsume(address target);
    error AccessManagerUnauthorizedCancel(address caller, address target);
    error AccessManagerInvalidInitialAdmin();
    error AccessManagerTargetCallFailed(address target);

    // ---- Constants accessors ----

    function ADMIN_ROLE() external pure returns (uint64);
    function PUBLIC_ROLE() external pure returns (uint64);

    // ---- Role queries ----

    function hasRole(uint64 roleId, address account) external view returns (bool isMember, uint32 executionDelay);
    function getAccess(uint64 roleId, address account)
        external
        view
        returns (uint48 since, uint32 currentDelay, uint32 pendingDelay, uint48 effect);
    function getRoleAdmin(uint64 roleId) external view returns (uint64);
    function getRoleGuardian(uint64 roleId) external view returns (uint64);
    function getRoleGrantDelay(uint64 roleId) external view returns (uint32);
    function getRoleMembers(uint64 roleId) external view returns (address[] memory);
    function getRoleMemberCount(uint64 roleId) external view returns (uint256);

    // ---- Target queries ----

    function getTargetFunctionRole(address target, bytes4 selector) external view returns (uint64);
    function getTargetAdminDelay(address target) external view returns (uint32);
    function isTargetClosed(address target) external view returns (bool);

    // ---- Authority queries ----

    function canCall(address caller, address target, bytes4 selector)
        external
        view
        returns (bool immediate, uint32 delay);
    function hashOperation(address caller, address target, bytes calldata data) external pure returns (bytes32);
    function getSchedule(bytes32 operationId) external view returns (uint48);
    function getNonce(bytes32 operationId) external view returns (uint32);

    // ---- Role management ----

    function grantRole(uint64 roleId, address account, uint32 executionDelay) external;
    function revokeRole(uint64 roleId, address account) external;
    function renounceRole(uint64 roleId, address callerConfirmation) external;
    function setRoleAdmin(uint64 roleId, uint64 admin) external;
    function setRoleGuardian(uint64 roleId, uint64 guardian) external;
    function setGrantDelay(uint64 roleId, uint32 newDelay) external;
    function labelRole(uint64 roleId, string calldata label) external;

    // ---- Target management ----

    function setTargetFunctionRole(address target, bytes4[] calldata selectors, uint64 roleId) external;
    function setTargetAdminDelay(address target, uint32 newDelay) external;
    function setTargetClosed(address target, bool closed) external;

    // ---- Operation scheduling ----

    function schedule(address target, bytes calldata data, uint48 when)
        external
        returns (bytes32 operationId, uint32 nonce);
    function execute(address target, bytes calldata data) external payable returns (uint32 nonce);
    function cancel(address caller, address target, bytes calldata data) external returns (uint32 nonce);
}
