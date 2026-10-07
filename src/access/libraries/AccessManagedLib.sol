// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAccessManaged} from "@lattice/interfaces/access/IAccessManaged.sol";
import {IAccessManager} from "@lattice/interfaces/access/IAccessManager.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.AccessManaged")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ACCESS_MANAGED_STORAGE_SLOT = 0x1d3b28af968dd6edd45cccd73c2668243fb5bd57c6ee16239765b74aa3d5e100;

/// @dev `0x4a531f33` is `type(IAccessManaged).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x4a531f33), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IACCESSMANAGED_SLOT = 0x97f7b4db7c24da5392018b796b53913aa0747b5c0b28d3c6627e928edcc14372;

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
        if (msg.sender != accessManagedStorage()._authority) {
            revert IAccessManaged.AccessManagedUnauthorized(msg.sender);
        }
        if (newAuthority == address(0)) revert IAccessManaged.AccessManagedInvalidAuthority(address(0));
        if (newAuthority.code.length == 0) revert IAccessManaged.AccessManagedInvalidAuthority(newAuthority);
        accessManagedStorage()._authority = newAuthority;
        emit IAccessManaged.AuthorityUpdated(newAuthority);
    }

    /// @notice Returns {IS_CONSUMING_SCHEDULED_OP_SELECTOR} while `_consumingScheduledOp` is set, else `0`.
    /// @dev OZ semantics: the flag is set only while a delayed direct call consumes its scheduled operation on
    ///      the authority, so the authority can confirm the request came from this target. Nothing sets it until
    ///      the authority exposes `consumeScheduledOp` (issue #219); it never bypasses {restrictedCheck}.
    function isConsumingScheduledOp() internal view returns (bytes4) {
        return accessManagedStorage()._consumingScheduledOp ? IS_CONSUMING_SCHEDULED_OP_SELECTOR : bytes4(0);
    }

    /// @notice Library-call gate. Reverts unless the authority lets `msg.sender` call `msg.sig` on this contract
    ///         immediately. Calls the manager makes from `execute` pass because the authority accepts itself as
    ///         caller for the (target, selector) it is executing; there is no target-side bypass.
    function restrictedCheck() internal view {
        address caller = msg.sender;
        (bool immediate, uint32 delay) =
            IAccessManager(accessManagedStorage()._authority).canCall(caller, address(this), msg.sig);
        if (immediate && delay == 0) return;
        if (delay > 0) {
            revert IAccessManaged.AccessManagedRequiredDelay(caller, delay);
        }
        revert IAccessManaged.AccessManagedUnauthorized(caller);
    }
}
