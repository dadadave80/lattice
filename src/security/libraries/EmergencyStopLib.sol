// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IEmergencyStop} from "@lattice/interfaces/IEmergencyStop.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.EmergencyStop")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant EMERGENCY_STOP_STORAGE_SLOT = 0x06261d2148a76026572818ff69ded6332eb2830e669ce15f15f286b1d91c5800;

/// @dev `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant EMERGENCY_STOP_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x9e464da9 is `type(IEmergencyStop).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x9e464da9), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IEMERGENCYSTOP_SLOT = 0x59d8ae278aff771bb9e56436652ef8f684d37f52855acb66dfe58a5a44c4d9de;

/// @dev Role identifier for emergency guardians. Any address with this role can trip the stop.
bytes32 constant EMERGENCY_GUARDIAN_ROLE = keccak256("EMERGENCY_GUARDIAN_ROLE");

/// @notice Top-level storage struct for the EmergencyStop module.
/// @custom:storage-location erc7201:lattice.storage.EmergencyStop
struct EmergencyStopStorage {
    bool _stopped;
    string _reason;
}

/// @title EmergencyStop Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Pausable.sol)
/// @notice Library implementing a multi-guardian emergency stop for Diamond facets.
/// @dev Any address holding the `EMERGENCY_GUARDIAN_ROLE` can activate the stop.
///      Only an address holding `DEFAULT_ADMIN_ROLE` can resume operations.
///      Guardian management (add/remove) is also restricted to the admin.
///      The guardian roster is stored in the AccessControl role mapping — no
///      separate storage is required in this module.
library EmergencyStopLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                          EMERGENCY STOP STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the storage struct for EmergencyStop at its ERC-7201 slot.
    function emergencyStopStorage() internal pure returns (EmergencyStopStorage storage $) {
        assembly {
            $.slot := EMERGENCY_STOP_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IEmergencyStop interface via ERC-165.
    /// @dev Writes `true` to the precomputed ERC-165 map slot.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IEMERGENCYSTOP_SLOT, true)
        }
    }

    /// @notice Initializes the EmergencyStop module.
    /// @dev Must be called between `InitializableLib.preInitializer` and `postInitializer`.
    ///      Registers the IEmergencyStop interface ID for ERC-165 discovery.
    function __EmergencyStop_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         EMERGENCY STOP OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Activates the emergency stop.
    /// @dev Reverts with `EmergencyStopUnauthorizedGuardian` if caller lacks guardian role.
    ///      Reverts with `EmergencyStopActive` if the stop is already active.
    ///      Emits `EmergencyStopped`.
    /// @param reason A human-readable description of why the stop is triggered.
    function emergencyStop(string calldata reason) internal {
        address caller = ContextLib.msgSender();
        if (!AccessControlLib.hasRole(EMERGENCY_GUARDIAN_ROLE, caller)) {
            revert IEmergencyStop.EmergencyStopUnauthorizedGuardian(caller);
        }
        _emergencyStop(reason, caller);
    }

    /// @notice Resumes operations after an emergency stop.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Reverts with `EmergencyStopNotActive` if not stopped.
    ///      Emits `EmergencyResumed`.
    function emergencyResume() internal {
        AccessControlLib.checkRole(0x00);
        _emergencyResume();
    }

    /// @notice Grants the guardian role to `guardian`.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Emits `GuardianAdded` only if the role was not already held.
    ///      Note: when a new guardian is successfully added, both `IAccessControl.RoleGranted`
    ///      (from AccessControlLib._grantRole) and `IEmergencyStop.GuardianAdded` are emitted.
    ///      Off-chain systems that track guardians should follow exactly one of these events
    ///      to avoid double-counting.
    /// @param guardian The address to grant guardian status.
    function addGuardian(address guardian) internal {
        AccessControlLib.checkRole(0x00);
        bool changed = AccessControlLib._grantRole(EMERGENCY_GUARDIAN_ROLE, guardian);
        if (changed) {
            emit IEmergencyStop.GuardianAdded(guardian);
        }
    }

    /// @notice Revokes the guardian role from `guardian`.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Emits `GuardianRemoved` only if the address held the role.
    ///      Note: on successful removal both `IAccessControl.RoleRevoked` and
    ///      `IEmergencyStop.GuardianRemoved` are emitted — follow exactly one for off-chain indexing.
    /// @param guardian The address to revoke guardian status from.
    function removeGuardian(address guardian) internal {
        AccessControlLib.checkRole(0x00);
        bool changed = AccessControlLib._revokeRole(EMERGENCY_GUARDIAN_ROLE, guardian);
        if (changed) {
            emit IEmergencyStop.GuardianRemoved(guardian);
        }
    }

    /// @notice Reverts with `EmergencyStopActive` if the emergency stop is active.
    /// @dev Consumer modules call this to gate protected operations.
    function checkNotStopped() internal view {
        if (emergencyStopStorage()._stopped) {
            revert IEmergencyStop.EmergencyStopActive();
        }
    }

    /// @notice Returns whether the emergency stop is currently active.
    /// @return bool True if the system is stopped, false otherwise.
    function isStopped() internal view returns (bool) {
        return emergencyStopStorage()._stopped;
    }

    /// @notice Returns whether `account` holds the guardian role.
    /// @param account The address to query.
    /// @return bool True if the account is a guardian.
    function isGuardian(address account) internal view returns (bool) {
        return AccessControlLib.hasRole(EMERGENCY_GUARDIAN_ROLE, account);
    }

    /// @notice Returns the reason string recorded when the stop was last triggered.
    /// @return string The reason for the last emergency stop (empty if never stopped/cleared).
    function stoppedReason() internal view returns (string memory) {
        return emergencyStopStorage()._reason;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Internal — sets stopped flag and reason, emits EmergencyStopped.
    function _emergencyStop(string calldata reason, address guardian) internal {
        if (emergencyStopStorage()._stopped) revert IEmergencyStop.EmergencyStopActive();
        emergencyStopStorage()._stopped = true;
        emergencyStopStorage()._reason = reason;
        emit IEmergencyStop.EmergencyStopped(guardian, reason);
    }

    /// @notice Internal — clears stopped flag and reason, emits EmergencyResumed.
    function _emergencyResume() internal {
        if (!emergencyStopStorage()._stopped) revert IEmergencyStop.EmergencyStopNotActive();
        emergencyStopStorage()._stopped = false;
        delete emergencyStopStorage()._reason;
        emit IEmergencyStop.EmergencyResumed(ContextLib.msgSender());
    }
}
