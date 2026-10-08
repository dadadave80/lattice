// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAccessManager
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/manager/IAccessManager.sol)
/// @notice Centralized authority: roles, hierarchies, grant/execution delays,
///         per-target function-selector permissions, operation scheduling.
///         Follows OpenZeppelin v5 AccessManager, including its admin restrictions: `setTargetFunctionRole`,
///         `setTargetClosed` and `updateAuthority` carry the target's admin delay, `grantRole`/`revokeRole` are
///         restricted to the role's admin, and a non-zero required delay (the larger of that delay and the caller's
///         execution delay) means the call must be scheduled against this manager, then made directly or through
///         `execute` once ready. A schedule expires 1 week after it is ready, that second included.
///         As in OZ, the admin delay on `updateAuthority` does not bind `execute(target, setAuthority(x))`, which is
///         gated by the target's own role for `setAuthority` (ADMIN_ROLE unless mapped). To make the admin delay an
///         exit window for authority migration, map the target's `setAuthority` selector to a role nobody holds;
///         undoing that mapping is itself subject to the admin delay.
/// @dev Differences from OpenZeppelin v5.1.0: ADMIN_ROLE is held only by the initial admin and cannot be granted,
///      revoked or renounced; errors keep the Lattice shapes (`AccessManagerUnauthorizedAccount` where OZ has
///      `AccessManagerUnauthorizedCall`, `AccessManagerTargetCallFailed` for a target that reverts without data,
///      and a `schedule` by a caller with immediate access reverts `AccessManagerNotScheduled`); `execute` does not
///      reject a target without code (OZ reverts `AddressEmptyCode`); `schedule` raises
///      a too-early `when` to the earliest allowed time instead of reverting; nonces come from one global counter;
///      re-granting a member applies a new execution delay at once (OZ delays a decrease by the difference); and
///      `expiration()`/`minSetback()` are not exposed (1 week and 5 days). In a diamond, `address(this)` also hosts
///      the other facets, so a call `execute` makes to the diamond with a selector that is not one of this
///      manager's admin functions is gated by the diamond's own target roles (see issue #240). Those default to
///      ADMIN_ROLE, and the call arrives with `msg.sender == address(this)`, so a co-cut ADMIN_ROLE holder acts as
///      the diamond itself on every other facet: it passes any gate that trusts the diamond as caller, such as
///      GovernedDiamondCut's UPGRADE_EXECUTOR_ROLE, the timelock's self-only setters and the ERC-7786 handlers.
///      Keep the manager in its own authority diamond; to govern it, make the governed diamond that authority's
///      initial admin (ADMIN_ROLE cannot be granted later). Do not make a co-cut manager's own diamond its admin:
///      the manager refuses that caller outside an `execute` already in flight, so it could never be configured.
///      See "Composition hazards" in docs/guides/compose-your-own-diamond.md.
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

    // ---- Managed targets ----

    /// @notice Points managed `target` at `newAuthority`. Only callable by `ADMIN_ROLE`; this manager must be
    ///         `target`'s current authority.
    function updateAuthority(address target, address newAuthority) external;

    // ---- Operation scheduling ----

    function schedule(address target, bytes calldata data, uint48 when)
        external
        returns (bytes32 operationId, uint32 nonce);
    function execute(address target, bytes calldata data) external payable returns (uint32 nonce);
    function cancel(address caller, address target, bytes calldata data) external returns (uint32 nonce);

    /// @notice Consumes the scheduled operation (`caller`, `msg.sender`, `data`) for a managed target making a
    ///         delayed direct call. Reverts {AccessManagerUnauthorizedConsume} unless `msg.sender` reports
    ///         `isConsumingScheduledOp.selector` from {IAccessManaged-isConsumingScheduledOp}, and reverts unless
    ///         the operation is scheduled, ready and not expired.
    function consumeScheduledOp(address caller, bytes calldata data) external;
}
