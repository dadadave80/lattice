// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControlTimed} from "@lattice/interfaces/access/IAccessControlTimed.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.AccessControlTimed")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ACCESS_CONTROL_TIMED_STORAGE_SLOT = 0xc28360e6402e1e090270be0970bdf75960435f822fc9a49d7b8c286806e6af00;

/// @dev 0x55658261 is `type(IAccessControlTimed).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x55658261), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IACCESSCONTROLTIMED_SLOT =
    0x6389d98b1603c26ed93ee23dd27c7d50ce87ec4985c6f5adaf89a862d65f1d7e;

struct Timing {
    uint48 start;
    uint48 expires; // 0 means untimed (timeless after start)
}

/// @custom:storage-location erc7201:lattice.storage.AccessControlTimed
struct AccessControlTimedStorage {
    mapping(bytes32 role => mapping(address account => Timing)) _timings;
}

/// @title AccessControlTimedLib
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol)
/// @notice Extension of AccessControlLib: per-grant (start, expires) windows.
library AccessControlTimedLib {
    function accessControlTimedStorage() internal pure returns (AccessControlTimedStorage storage $) {
        assembly {
            $.slot := ACCESS_CONTROL_TIMED_STORAGE_SLOT
        }
    }

    function __AccessControlTimed_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IACCESSCONTROLTIMED_SLOT, true)
        }
    }

    // ---- Reads ----

    function hasRole(bytes32 role, address account) internal view returns (bool) {
        if (!AccessControlLib.hasRole(role, account)) return false;
        Timing storage t = accessControlTimedStorage()._timings[role][account];
        if (block.timestamp < t.start) return false;
        if (t.expires != 0 && block.timestamp > t.expires) return false;
        return true;
    }

    function roleExpiration(bytes32 role, address account) internal view returns (uint48 start, uint48 expires) {
        Timing storage t = accessControlTimedStorage()._timings[role][account];
        return (t.start, t.expires);
    }

    // ---- Mutations ----

    function grantRole(bytes32 _role, address _account) internal {
        AccessControlLib.checkRole(AccessControlLib.getRoleAdmin(_role));
        _grantRoleTimed(_role, _account, uint48(block.timestamp), 0);
    }

    function grantRoleTimed(bytes32 _role, address _account, uint48 _start, uint48 _expires) internal {
        AccessControlLib.checkRole(AccessControlLib.getRoleAdmin(_role));
        _grantRoleTimed(_role, _account, _start, _expires);
    }

    function extendRole(bytes32 _role, address _account, uint48 _newExpires) internal {
        AccessControlLib.checkRole(AccessControlLib.getRoleAdmin(_role));
        _extendRole(_role, _account, _newExpires);
    }

    function revokeRole(bytes32 _role, address _account) internal {
        AccessControlLib.checkRole(AccessControlLib.getRoleAdmin(_role));
        _revokeRole(_role, _account);
    }

    function _grantRoleTimed(bytes32 role, address account, uint48 start, uint48 expires) internal {
        if (expires != 0) {
            if (expires <= block.timestamp) revert IAccessControlTimed.AccessControlTimedExpiryInPast(expires);
            if (expires < start) revert IAccessControlTimed.AccessControlTimedInvalidWindow(start, expires);
        }
        AccessControlLib._grantRole(role, account); // emits RoleGranted if storage changed
        accessControlTimedStorage()._timings[role][account] = Timing({start: start, expires: expires});
        // Suppress RoleGrantedTimed for a plain timeless grant (start == now, expires == 0):
        // the RoleGranted event from _grantRole already conveys all the information.
        // Emitting RoleGrantedTimed here would confuse off-chain indexers with a redundant event.
        if (!(start == block.timestamp && expires == 0)) {
            emit IAccessControlTimed.RoleGrantedTimed(role, account, msg.sender, start, expires);
        }
    }

    function _extendRole(bytes32 role, address account, uint48 newExpires) internal {
        // Use time-aware hasRole to reject expired grants (base storage still has them).
        if (!hasRole(role, account)) {
            revert IAccessControlTimed.AccessControlTimedRoleNotHeld(role, account);
        }
        Timing storage t = accessControlTimedStorage()._timings[role][account];
        // Guard: extendRole is only valid on already-timed grants.
        // Silently converting a timeless grant (expires == 0 means "never expires") into
        // a timed one would degrade a permanent privilege — require explicit grantRoleTimed.
        if (t.expires == 0) {
            revert IAccessControlTimed.AccessControlTimedRoleIsTimeless(role, account);
        }
        if (newExpires <= t.expires) {
            revert IAccessControlTimed.AccessControlTimedExpiryNotExtended(t.expires, newExpires);
        }
        t.expires = newExpires;
        emit IAccessControlTimed.RoleExpiryUpdated(role, account, msg.sender, newExpires);
    }

    function _revokeRole(bytes32 role, address account) internal {
        AccessControlLib._revokeRole(role, account); // emits RoleRevoked if storage changed
        delete accessControlTimedStorage()._timings[role][account];
    }
}
