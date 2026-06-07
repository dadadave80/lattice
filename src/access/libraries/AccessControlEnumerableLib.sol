// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.AccessControlEnumerable")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ACCESS_CONTROL_ENUMERABLE_STORAGE_SLOT =
    0xae7c738306b742461a657cbf6c6b56bd5351917d4cf69da559703284f7d34500;

/// @dev `0xf92172dc` is `type(IAccessControlEnumerable).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xf92172dc), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IACCESSCONTROLENUMERABLE_SLOT =
    0xdfb0020c4bf380ed4a6e172ee8a12845bb7e78959d456aee21dd4cc4e0a60edf;

/// @custom:storage-location erc7201:lattice.storage.AccessControlEnumerable
struct AccessControlEnumerableStorage {
    mapping(bytes32 role => EnumerableSet.AddressSet) _roleMembers;
}

/// @title AccessControlEnumerableLib
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/extensions/AccessControlEnumerable.sol)
/// @notice Extension of AccessControlLib: per-role address enumeration.
library AccessControlEnumerableLib {
    using EnumerableSet for EnumerableSet.AddressSet;

    function accessControlEnumerableStorage() internal pure returns (AccessControlEnumerableStorage storage $) {
        assembly {
            $.slot := ACCESS_CONTROL_ENUMERABLE_STORAGE_SLOT
        }
    }

    function __AccessControlEnumerable_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IACCESSCONTROLENUMERABLE_SLOT, true)
        }
    }

    // ---- Reads ----

    function getRoleMember(bytes32 role, uint256 index) internal view returns (address) {
        return accessControlEnumerableStorage()._roleMembers[role].at(index);
    }

    function getRoleMemberCount(bytes32 role) internal view returns (uint256) {
        return accessControlEnumerableStorage()._roleMembers[role].length();
    }

    function getRoleMembers(bytes32 role) internal view returns (address[] memory) {
        return accessControlEnumerableStorage()._roleMembers[role].values();
    }

    // ---- Mutations ----

    function grantRole(bytes32 _role, address _account) internal {
        AccessControlLib.checkRole(AccessControlLib.getRoleAdmin(_role));
        _grantRole(_role, _account);
    }

    function revokeRole(bytes32 _role, address _account) internal {
        AccessControlLib.checkRole(AccessControlLib.getRoleAdmin(_role));
        _revokeRole(_role, _account);
    }

    function renounceRole(bytes32 role, address callerConfirmation) internal {
        if (callerConfirmation != ContextLib.msgSender()) {
            revert IAccessControl.AccessControlBadConfirmation();
        }
        _revokeRole(role, callerConfirmation);
    }

    function _grantRole(bytes32 role, address account) internal returns (bool granted) {
        granted = AccessControlLib._grantRole(role, account); // emits RoleGranted if changed
        if (granted) {
            accessControlEnumerableStorage()._roleMembers[role].add(account);
        }
    }

    function _revokeRole(bytes32 role, address account) internal returns (bool revoked) {
        revoked = AccessControlLib._revokeRole(role, account); // emits RoleRevoked if changed
        if (revoked) {
            accessControlEnumerableStorage()._roleMembers[role].remove(account);
        }
    }
}
