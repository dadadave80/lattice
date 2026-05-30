// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";

/// @title IAccessControlDefaultAdminRules
/// @notice Timelocked transfer of DEFAULT_ADMIN_ROLE. The admin identity is sourced from
///         `OwnableLib.owner()`; grant/revoke of DEFAULT_ADMIN_ROLE is disabled in favor of
///         the begin/accept flow guarded by a configurable delay.
interface IAccessControlDefaultAdminRules is IAccessControl {
    event DefaultAdminTransferScheduled(address indexed newAdmin, uint48 readyAt);
    event DefaultAdminTransferCanceled();
    event DefaultAdminDelayChangeScheduled(uint48 newDelay, uint48 readyAt);
    event DefaultAdminDelayChangeCanceled();

    error AccessControlDefaultAdminRulesUseAdminTransfer();
    error AccessControlDefaultAdminRulesUnauthorizedAccept();
    error AccessControlDefaultAdminRulesInvalidNewAdmin(address newAdmin);

    function defaultAdmin() external view returns (address);
    function pendingDefaultAdmin() external view returns (address newAdmin, uint48 readyAt);
    function defaultAdminDelay() external view returns (uint48);
    function pendingDefaultAdminDelay() external view returns (uint48 newDelay, uint48 readyAt);
    function defaultAdminDelayIncreaseWait() external pure returns (uint48);

    function beginDefaultAdminTransfer(address newAdmin) external;
    function cancelDefaultAdminTransfer() external;
    function acceptDefaultAdminTransfer() external;
    function changeDefaultAdminDelay(uint48 newDelay) external;
    function rollbackDefaultAdminDelay() external;
}
