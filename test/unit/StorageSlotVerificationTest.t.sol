// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

// ERC-7201 storage slot constants under test
import {
    ACCESS_CONTROL_DEFAULT_ADMIN_RULES_STORAGE_SLOT,
    ERC165_MAP_IACCESSCONTROLDEFAULTADMINRULES_SLOT
} from "@lattice/access/libraries/AccessControlDefaultAdminRulesLib.sol";
import {
    ACCESS_CONTROL_ENUMERABLE_STORAGE_SLOT,
    ERC165_MAP_IACCESSCONTROLENUMERABLE_SLOT
} from "@lattice/access/libraries/AccessControlEnumerableLib.sol";
import {
    ACCESS_CONTROL_STORAGE_SLOT,
    ERC165_MAP_IACCESSCONTROL_SLOT,
    ERC165_STORAGE_LOCATION
} from "@lattice/access/libraries/AccessControlLib.sol";
import {
    ACCESS_CONTROL_TIMED_STORAGE_SLOT,
    ERC165_MAP_IACCESSCONTROLTIMED_SLOT
} from "@lattice/access/libraries/AccessControlTimedLib.sol";
import {
    ACCESS_MANAGED_STORAGE_SLOT,
    ERC165_MAP_IACCESSMANAGED_SLOT
} from "@lattice/access/libraries/AccessManagedLib.sol";
import {
    ACCESS_MANAGER_STORAGE_SLOT,
    ERC165_MAP_IACCESSMANAGER_SLOT
} from "@lattice/access/libraries/AccessManagerLib.sol";

import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IAccessControlDefaultAdminRules} from "@lattice/interfaces/IAccessControlDefaultAdminRules.sol";
import {IAccessControlEnumerable} from "@lattice/interfaces/IAccessControlEnumerable.sol";
import {IAccessControlTimed} from "@lattice/interfaces/IAccessControlTimed.sol";
import {IAccessManaged} from "@lattice/interfaces/IAccessManaged.sol";
import {IAccessManager} from "@lattice/interfaces/IAccessManager.sol";

/// @title StorageSlotVerificationTest
/// @notice Re-derives every ERC-7201 storage slot and ERC-165 map slot from first principles
///         and asserts equality against the declared constants. A mismatch here means a module's
///         storage slot constant is wrong and would collide with another module's storage. (L-4)
contract StorageSlotVerificationTest is Test {
    // ---- ERC-7201 slot derivation helper ----

    function _erc7201Slot(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff));
    }

    // ---- ERC-165 map slot derivation helper ----

    function _erc165MapSlot(bytes4 interfaceId, bytes32 erc165Storage) internal pure returns (bytes32) {
        return keccak256(abi.encode(interfaceId, erc165Storage));
    }

    // ======================== ERC-7201 Storage Slots ========================

    function test_AccessControlStorageSlot() public pure {
        bytes32 expected = _erc7201Slot("openzeppelin.storage.AccessControl");
        assertEq(ACCESS_CONTROL_STORAGE_SLOT, expected, "AccessControl storage slot mismatch");
    }

    function test_AccessControlEnumerableStorageSlot() public pure {
        bytes32 expected = _erc7201Slot("lattice.storage.AccessControlEnumerable");
        assertEq(ACCESS_CONTROL_ENUMERABLE_STORAGE_SLOT, expected, "AccessControlEnumerable storage slot mismatch");
    }

    function test_AccessControlTimedStorageSlot() public pure {
        bytes32 expected = _erc7201Slot("lattice.storage.AccessControlTimed");
        assertEq(ACCESS_CONTROL_TIMED_STORAGE_SLOT, expected, "AccessControlTimed storage slot mismatch");
    }

    function test_AccessControlDefaultAdminRulesStorageSlot() public pure {
        bytes32 expected = _erc7201Slot("lattice.storage.AccessControlDefaultAdminRules");
        assertEq(
            ACCESS_CONTROL_DEFAULT_ADMIN_RULES_STORAGE_SLOT,
            expected,
            "AccessControlDefaultAdminRules storage slot mismatch"
        );
    }

    function test_AccessManagerStorageSlot() public pure {
        bytes32 expected = _erc7201Slot("lattice.storage.AccessManager");
        assertEq(ACCESS_MANAGER_STORAGE_SLOT, expected, "AccessManager storage slot mismatch");
    }

    function test_AccessManagedStorageSlot() public pure {
        bytes32 expected = _erc7201Slot("lattice.storage.AccessManaged");
        assertEq(ACCESS_MANAGED_STORAGE_SLOT, expected, "AccessManaged storage slot mismatch");
    }

    // ======================== ERC-165 Map Slots ========================

    function test_Erc165StorageLocation() public pure {
        bytes32 expected = _erc7201Slot("diamond.lib.storage.ERC165");
        assertEq(ERC165_STORAGE_LOCATION, expected, "ERC165 storage location mismatch");
    }

    function test_Erc165MapIAccessControlSlot() public pure {
        bytes4 interfaceId = type(IAccessControl).interfaceId;
        bytes32 expected = _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION);
        assertEq(ERC165_MAP_IACCESSCONTROL_SLOT, expected, "ERC165 IAccessControl map slot mismatch");
    }

    function test_Erc165MapIAccessControlEnumerableSlot() public pure {
        bytes4 interfaceId = type(IAccessControlEnumerable).interfaceId;
        assertEq(interfaceId, bytes4(0xf92172dc), "IAccessControlEnumerable interfaceId comment is stale");
        bytes32 expected = _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION);
        assertEq(
            ERC165_MAP_IACCESSCONTROLENUMERABLE_SLOT, expected, "ERC165 IAccessControlEnumerable map slot mismatch"
        );
    }

    function test_Erc165MapIAccessControlTimedSlot() public pure {
        bytes4 interfaceId = type(IAccessControlTimed).interfaceId;
        bytes32 expected = _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION);
        assertEq(ERC165_MAP_IACCESSCONTROLTIMED_SLOT, expected, "ERC165 IAccessControlTimed map slot mismatch");
    }

    function test_Erc165MapIAccessControlDefaultAdminRulesSlot() public pure {
        bytes4 interfaceId = type(IAccessControlDefaultAdminRules).interfaceId;
        bytes32 expected = _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION);
        assertEq(
            ERC165_MAP_IACCESSCONTROLDEFAULTADMINRULES_SLOT,
            expected,
            "ERC165 IAccessControlDefaultAdminRules map slot mismatch"
        );
    }

    function test_Erc165MapIAccessManagerSlot() public pure {
        bytes4 interfaceId = type(IAccessManager).interfaceId;
        bytes32 expected = _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION);
        assertEq(ERC165_MAP_IACCESSMANAGER_SLOT, expected, "ERC165 IAccessManager map slot mismatch");
    }

    function test_Erc165MapIAccessManagedSlot() public pure {
        bytes4 interfaceId = type(IAccessManaged).interfaceId;
        bytes32 expected = _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION);
        assertEq(ERC165_MAP_IACCESSMANAGED_SLOT, expected, "ERC165 IAccessManaged map slot mismatch");
    }

    // ======================== Uniqueness Check ========================

    function test_AllErc7201SlotsAreUnique() public pure {
        bytes32[6] memory slots = [
            ACCESS_CONTROL_STORAGE_SLOT,
            ACCESS_CONTROL_ENUMERABLE_STORAGE_SLOT,
            ACCESS_CONTROL_TIMED_STORAGE_SLOT,
            ACCESS_CONTROL_DEFAULT_ADMIN_RULES_STORAGE_SLOT,
            ACCESS_MANAGER_STORAGE_SLOT,
            ACCESS_MANAGED_STORAGE_SLOT
        ];
        for (uint256 i; i < slots.length; ++i) {
            for (uint256 j = i + 1; j < slots.length; ++j) {
                assertTrue(slots[i] != slots[j], "Duplicate ERC-7201 storage slot detected");
            }
        }
    }
}
