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

/// @dev `0xe5b444fd` is `type(IAccessManaged).interfaceId` (includes setConsumingScheduledOp).
/// `keccak256(abi.encode(bytes4(0xe5b444fd), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IACCESSMANAGED_SLOT = 0x18229ea668ffe17715e3d827216c081ca3411cbbb4f8a9b8908fb47aee1d7887;

/// @custom:storage-location erc7201:lattice.storage.AccessManaged
struct AccessManagedStorage {
    address _authority;
    bool _consumingScheduledOp;
}

/// @title AccessManagedLib
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/manager/AccessManaged.sol)
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
        if (initialAuthority.code.length == 0) revert IAccessManaged.AccessManagedInvalidAuthority(initialAuthority);
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
        if (newAuthority.code.length == 0) revert IAccessManaged.AccessManagedInvalidAuthority(newAuthority);
        accessManagedStorage()._authority = newAuthority;
        emit IAccessManaged.AuthorityUpdated(newAuthority);
    }

    function isConsumingScheduledOp() internal view returns (bytes4) {
        return accessManagedStorage()._consumingScheduledOp ? IS_CONSUMING_SCHEDULED_OP_SELECTOR : bytes4(0);
    }

    /// @notice Sets the `_consumingScheduledOp` flag. Only callable by the authority.
    /// @dev Called by AccessManager.execute() before and after invoking a restricted function,
    ///      so that `restrictedCheck()` skips the canCall gate during manager-driven execution.
    function setConsumingScheduledOp(bool consuming) internal {
        AccessManagedStorage storage $ = accessManagedStorage();
        if (ContextLib.msgSender() != $._authority) {
            revert IAccessManaged.AccessManagedUnauthorized(ContextLib.msgSender());
        }
        $._consumingScheduledOp = consuming;
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
