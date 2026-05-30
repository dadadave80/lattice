// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IAccessControlDefaultAdminRules} from "@lattice/interfaces/IAccessControlDefaultAdminRules.sol";
import {TimelockLib} from "@lattice/utils/libraries/TimelockLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.AccessControlDefaultAdminRules")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ACCESS_CONTROL_DEFAULT_ADMIN_RULES_STORAGE_SLOT =
    0x1765af7cf4b4926ea92d6bd1e63b3bdc2bf0c0080fcedc7a74681e95a003b600;

/// @dev 0x31498786 is `type(IAccessControlDefaultAdminRules).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x31498786), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IACCESSCONTROLDEFAULTADMINRULES_SLOT =
    0xb2f4dbac1cfd5c6afec79f3b850a4dd29e5512a036223ae15a9611619f4bb1db;

// 5 days. Wait imposed when a delay-increase is scheduled.
uint48 constant DELAY_INCREASE_WAIT = 5 days;

bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

/// @custom:storage-location erc7201:lattice.storage.AccessControlDefaultAdminRules
struct AccessControlDefaultAdminRulesStorage {
    address _pendingDefaultAdmin;
    TimelockLib.SingleSchedule _adminTransferSchedule;
    uint48 _currentDelay;
    uint48 _pendingDelay;
    TimelockLib.SingleSchedule _delayChangeSchedule;
}

/// @title AccessControlDefaultAdminRulesLib
/// @notice Timelocked admin transfer + configurable delay, sourcing admin from Ownable.
library AccessControlDefaultAdminRulesLib {
    using TimelockLib for TimelockLib.SingleSchedule;

    function accessControlDefaultAdminRulesStorage()
        internal
        pure
        returns (AccessControlDefaultAdminRulesStorage storage $)
    {
        assembly {
            $.slot := ACCESS_CONTROL_DEFAULT_ADMIN_RULES_STORAGE_SLOT
        }
    }

    /// @notice Initializes the AccessControlDefaultAdminRules module.
    /// @dev Must be called AFTER OwnableLib.initializeOwner() and AccessControlLib.__AccessControl_init()
    ///      so that the initial owner is already set and base ACL storage is in sync.
    function __AccessControlDefaultAdminRules_init(uint48 initialDelay) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        accessControlDefaultAdminRulesStorage()._currentDelay = initialDelay;
        // Ensure base ACL storage reflects the initial owner as DEFAULT_ADMIN_ROLE holder.
        // AccessControlLib.__AccessControl_init already granted this; the call is idempotent.
        address initialAdmin = defaultAdmin();
        if (initialAdmin != address(0)) {
            AccessControlLib._grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        }
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IACCESSCONTROLDEFAULTADMINRULES_SLOT, true)
        }
    }

    // ---- Views ----

    function defaultAdmin() internal view returns (address ownerAddr) {
        bytes32 slot = OwnableLib._OWNER_SLOT;
        assembly {
            ownerAddr := and(sload(slot), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    function pendingDefaultAdmin() internal view returns (address newAdmin, uint48 readyAt_) {
        AccessControlDefaultAdminRulesStorage storage $ = accessControlDefaultAdminRulesStorage();
        return ($._pendingDefaultAdmin, $._adminTransferSchedule.readyAt());
    }

    function defaultAdminDelay() internal view returns (uint48) {
        AccessControlDefaultAdminRulesStorage storage $ = accessControlDefaultAdminRulesStorage();
        if ($._delayChangeSchedule.isReady()) {
            return $._pendingDelay;
        }
        return $._currentDelay;
    }

    function pendingDefaultAdminDelay() internal view returns (uint48 newDelay, uint48 readyAt_) {
        AccessControlDefaultAdminRulesStorage storage $ = accessControlDefaultAdminRulesStorage();
        uint48 r = $._delayChangeSchedule.readyAt();
        if (r == 0) return (0, 0);
        return ($._pendingDelay, r);
    }

    function defaultAdminDelayIncreaseWait() internal pure returns (uint48) {
        return DELAY_INCREASE_WAIT;
    }

    // ---- Mutations ----

    function beginDefaultAdminTransfer(address newAdmin) internal {
        OwnableLib.checkOwner();
        if (newAdmin == address(0)) {
            revert IAccessControlDefaultAdminRules.AccessControlDefaultAdminRulesInvalidNewAdmin(address(0));
        }
        _consolidateDelay();
        AccessControlDefaultAdminRulesStorage storage $ = accessControlDefaultAdminRulesStorage();
        if ($._adminTransferSchedule.isPending()) {
            $._adminTransferSchedule.cancel();
        }
        $._pendingDefaultAdmin = newAdmin;
        uint48 readyAt = $._adminTransferSchedule.schedule($._currentDelay);
        emit IAccessControlDefaultAdminRules.DefaultAdminTransferScheduled(newAdmin, readyAt);
    }

    function cancelDefaultAdminTransfer() internal {
        OwnableLib.checkOwner();
        AccessControlDefaultAdminRulesStorage storage $ = accessControlDefaultAdminRulesStorage();
        $._adminTransferSchedule.cancel();
        $._pendingDefaultAdmin = address(0);
        emit IAccessControlDefaultAdminRules.DefaultAdminTransferCanceled();
    }

    function acceptDefaultAdminTransfer() internal {
        AccessControlDefaultAdminRulesStorage storage $ = accessControlDefaultAdminRulesStorage();
        if (ContextLib.msgSender() != $._pendingDefaultAdmin) {
            revert IAccessControlDefaultAdminRules.AccessControlDefaultAdminRulesUnauthorizedAccept();
        }
        $._adminTransferSchedule.consume();
        address newAdmin = $._pendingDefaultAdmin;
        $._pendingDefaultAdmin = address(0);
        address oldAdmin = defaultAdmin();
        OwnableLib.setOwner(newAdmin);
        // Sync base ACL storage so checkRole(DEFAULT_ADMIN_ROLE) and grantRole/revokeRole
        // reflect the new admin. Without this, old admin retains power in base storage
        // while hasRole() (which reads Ownable) correctly shows new admin — H-2.
        AccessControlLib._revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
        AccessControlLib._grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
    }

    function changeDefaultAdminDelay(uint48 newDelay) internal {
        OwnableLib.checkOwner();
        AccessControlDefaultAdminRulesStorage storage $ = accessControlDefaultAdminRulesStorage();
        _consolidateDelay();
        uint48 wait_ = newDelay > $._currentDelay ? DELAY_INCREASE_WAIT : 0;
        if ($._delayChangeSchedule.isPending()) {
            $._delayChangeSchedule.cancel();
        }
        $._pendingDelay = newDelay;
        uint48 readyAt = $._delayChangeSchedule.schedule(wait_);
        emit IAccessControlDefaultAdminRules.DefaultAdminDelayChangeScheduled(newDelay, readyAt);
    }

    function rollbackDefaultAdminDelay() internal {
        OwnableLib.checkOwner();
        AccessControlDefaultAdminRulesStorage storage $ = accessControlDefaultAdminRulesStorage();
        $._delayChangeSchedule.cancel();
        $._pendingDelay = 0;
        emit IAccessControlDefaultAdminRules.DefaultAdminDelayChangeCanceled();
    }

    // ---- Internals ----

    function _consolidateDelay() private {
        AccessControlDefaultAdminRulesStorage storage $ = accessControlDefaultAdminRulesStorage();
        if ($._delayChangeSchedule.isReady()) {
            $._currentDelay = $._pendingDelay;
            $._pendingDelay = 0;
            $._delayChangeSchedule.cancel();
        }
    }
}
