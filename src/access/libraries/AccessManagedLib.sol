// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IAccessManaged} from "@lattice/interfaces/IAccessManaged.sol";
import {IAccessManager} from "@lattice/interfaces/IAccessManager.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.AccessManaged")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ACCESS_MANAGED_STORAGE_SLOT = 0x1d3b28af968dd6edd45cccd73c2668243fb5bd57c6ee16239765b74aa3d5e100;

/// @dev `0x4a531f33` is `type(IAccessManaged).interfaceId`.
bytes32 constant ERC165_MAP_IACCESSMANAGED_SLOT = 0x97f7b4db7c24da5392018b796b53913aa0747b5c0b28d3c6627e928edcc14372;

/// @custom:storage-location erc7201:lattice.storage.AccessManaged
struct AccessManagedStorage {
    address _authority;
    bool _consumingScheduledOp;
}

/// @title AccessManagedLib
/// @notice Companion library for contracts gated by an external AccessManager.
library AccessManagedLib {
    /// @notice `bytes4(keccak256("isConsumingScheduledOp()"))`.
    bytes4 internal constant IS_CONSUMING_SCHEDULED_OP_SELECTOR = 0x8fb36037;

    function accessManagedStorage() internal pure returns (AccessManagedStorage storage $) {
        assembly {
            $.slot := ACCESS_MANAGED_STORAGE_SLOT
        }
    }

    function __AccessManaged_init(address initialAuthority) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (initialAuthority == address(0)) revert IAccessManaged.AccessManagedInvalidAuthority(address(0));
        accessManagedStorage()._authority = initialAuthority;
        emit IAccessManaged.AuthorityUpdated(initialAuthority);
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IACCESSMANAGED_SLOT, true)
        }
    }

    function authority() internal view returns (address) {
        return accessManagedStorage()._authority;
    }

    function setAuthority(address newAuthority) internal {
        if (ContextLib.msgSender() != accessManagedStorage()._authority) {
            revert IAccessManaged.AccessManagedUnauthorized(ContextLib.msgSender());
        }
        if (newAuthority == address(0)) revert IAccessManaged.AccessManagedInvalidAuthority(address(0));
        accessManagedStorage()._authority = newAuthority;
        emit IAccessManaged.AuthorityUpdated(newAuthority);
    }

    function isConsumingScheduledOp() internal view returns (bytes4) {
        return accessManagedStorage()._consumingScheduledOp ? IS_CONSUMING_SCHEDULED_OP_SELECTOR : bytes4(0);
    }

    /// @notice Library-call gate. Reverts unless the caller is authorized.
    function restrictedCheck() internal view {
        AccessManagedStorage storage $ = accessManagedStorage();
        address caller = ContextLib.msgSender();
        address target = address(this);
        bytes4 selector = msg.sig;

        if ($._consumingScheduledOp) return;

        (bool immediate, uint32 delay) = IAccessManager($._authority).canCall(caller, target, selector);
        if (immediate && delay == 0) return;
        if (delay > 0) {
            revert IAccessManaged.AccessManagedRequiredDelay(caller, delay);
        }
        revert IAccessManaged.AccessManagedUnauthorized(caller);
    }
}
