// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ISessionKey} from "@lattice/interfaces/ISessionKey.sol";
import {Call} from "@lattice/interfaces/external/IERC7821.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.SessionKey")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant SESSION_KEY_STORAGE_SLOT = 0xd72f45b3818762a6cc49804ed52c577908badd7fff8bbd7849829b4fc764ae00;

/// @dev Wildcard sentinels: a permission registered with `ANY_TARGET` matches any target; with `ANY_SELECTOR`,
///      any selector.
address constant ANY_TARGET = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;
bytes4 constant ANY_SELECTOR = 0xffffffff;

/// @dev Native-value spend sentinel (the conventional "ETH" pseudo-address).
address constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

/// @dev ERC-20 selectors used for direct-transfer spend accounting.
bytes4 constant _ERC20_TRANSFER = 0xa9059cbb; // transfer(address,uint256)
bytes4 constant _ERC20_TRANSFER_FROM = 0x23b872dd; // transferFrom(address,address,uint256)

/// @notice Per-key validity window. `validUntil == 0` means unregistered/revoked.
struct SessionKeyData {
    uint48 validAfter;
    uint48 validUntil;
}

/// @notice Cumulative spend cap + amount already spent for a `(key, token)`.
struct SpendLimit {
    uint256 cap;
    uint256 spent;
    bool configured;
}

/// @notice ERC-7201 namespaced storage for session keys.
/// @custom:storage-location erc7201:lattice.storage.SessionKey
struct SessionKeyStorage {
    /// @notice Validity window per key. APPEND-ONLY.
    mapping(address key => SessionKeyData) _keys;
    /// @notice Allowlist: `_allowed[key][keccak256(target, selector)]`. APPEND-ONLY.
    mapping(address key => mapping(bytes32 permHash => bool)) _allowed;
    /// @notice Per-token cumulative spend caps. APPEND-ONLY.
    mapping(address key => mapping(address token => SpendLimit)) _spend;
}

/// @title SessionKeyLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic + ERC-7201 storage for scoped, expiring session keys. A registered key authorizes a batch
///         through the ERC-7821 executor's signed-`opData` path when the key is within its validity window and
///         every call matches its `(target, selector)` allowlist.
/// @dev v1 enforces expiry + allowlist (with `ANY_*` wildcards). Per-token spend limits are a planned follow-on.
library SessionKeyLib {
    function sessionKeyStorage() internal pure returns (SessionKeyStorage storage $) {
        assembly {
            $.slot := SESSION_KEY_STORAGE_SLOT
        }
    }

    function __SessionKey_init() internal view {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers (or replaces) a session key with a validity window + a `(target, selector)` allowlist.
    function registerSessionKey(
        address key,
        uint48 validAfter,
        uint48 validUntil,
        ISessionKey.Permission[] calldata permissions
    ) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (key == address(0) || key == ANY_TARGET) revert ISessionKey.InvalidSessionKey();
        if (validUntil <= block.timestamp || validUntil <= validAfter) revert ISessionKey.InvalidExpiry();

        SessionKeyStorage storage $ = sessionKeyStorage();
        $._keys[key] = SessionKeyData(validAfter, validUntil);
        uint256 n = permissions.length;
        for (uint256 i; i < n; ++i) {
            $._allowed[key][_permHash(permissions[i].target, permissions[i].selector)] = true;
        }
        emit ISessionKey.SessionKeyRegistered(key, validAfter, validUntil, n);
    }

    /// @notice Revokes a session key (clears its validity window). Existing permission entries are inert once
    ///         the key is inactive.
    function revokeSessionKey(address key) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        delete sessionKeyStorage()._keys[key];
        emit ISessionKey.SessionKeyRevoked(key);
    }

    /// @notice Sets a cumulative spend cap for `(key, token)`, resetting the spent counter. Admin only.
    function setSpendLimit(address key, address token, uint256 cap) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        SpendLimit storage l = sessionKeyStorage()._spend[key][token];
        l.cap = cap;
        l.spent = 0;
        l.configured = true;
        emit ISessionKey.SpendLimitSet(key, token, cap);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function isSessionKeyActive(address key) internal view returns (bool) {
        SessionKeyData storage d = sessionKeyStorage()._keys[key];
        return d.validUntil != 0 && block.timestamp >= d.validAfter && block.timestamp <= d.validUntil;
    }

    function sessionKeyValidity(address key) internal view returns (uint48 validAfter, uint48 validUntil) {
        SessionKeyData storage d = sessionKeyStorage()._keys[key];
        return (d.validAfter, d.validUntil);
    }

    function isCallPermitted(address key, address target, bytes4 selector) internal view returns (bool) {
        mapping(bytes32 => bool) storage a = sessionKeyStorage()._allowed[key];
        return a[_permHash(target, selector)] || a[_permHash(ANY_TARGET, selector)]
            || a[_permHash(target, ANY_SELECTOR)] || a[_permHash(ANY_TARGET, ANY_SELECTOR)];
    }

    function spendLimit(address key, address token) internal view returns (uint256 cap, uint256 spent) {
        SpendLimit storage l = sessionKeyStorage()._spend[key][token];
        return (l.cap, l.spent);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               AUTHORIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Reverts unless `key` is active and every call in `calls` is permitted. Called by the executor
    ///         when a batch's signed-`opData` was produced by a session key rather than the owner.
    function authorizeBatch(address key, Call[] memory calls) internal {
        if (!isSessionKeyActive(key)) revert ISessionKey.SessionKeyNotActive(key);
        uint256 n = calls.length;
        for (uint256 i; i < n; ++i) {
            Call memory c = calls[i];
            bytes4 selector = _selector(c.data);
            if (!isCallPermitted(key, c.target, selector)) {
                revert ISessionKey.CallNotPermitted(key, c.target, selector);
            }
            if (c.value != 0) _accrueSpend(key, NATIVE_TOKEN, c.value);
            (address token, uint256 amount) = _decodeErc20Spend(c.target, c.data);
            if (amount != 0) _accrueSpend(key, token, amount);
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Accrues `amount` of `token` against `key`'s cap; no-op if the token is uncapped. Reverts
    ///         {SpendLimitExceeded} once cumulative spend would exceed the cap.
    function _accrueSpend(address key, address token, uint256 amount) private {
        SpendLimit storage l = sessionKeyStorage()._spend[key][token];
        if (!l.configured) return;
        uint256 spent = l.spent + amount;
        if (spent > l.cap) revert ISessionKey.SpendLimitExceeded(key, token, l.cap, spent);
        l.spent = spent;
    }

    /// @notice Decodes a direct ERC-20 spend of the account's own balance from a call: `transfer(to, amount)`
    ///         or `transferFrom(address(this), to, amount)`. Returns `amount == 0` for anything else (indirect
    ///         spending is bounded by the allowlist, not here).
    function _decodeErc20Spend(address target, bytes memory data) private view returns (address token, uint256 amount) {
        bytes4 sel = _selector(data);
        if (sel == _ERC20_TRANSFER && data.length >= 0x44) {
            assembly {
                amount := mload(add(data, 0x44))
            }
            return (target, amount);
        }
        if (sel == _ERC20_TRANSFER_FROM && data.length >= 0x64) {
            address from;
            assembly {
                from := and(mload(add(data, 0x24)), 0xffffffffffffffffffffffffffffffffffffffff)
                amount := mload(add(data, 0x64))
            }
            if (from == address(this)) return (target, amount);
        }
        return (target, 0);
    }

    function _permHash(address target, bytes4 selector) private pure returns (bytes32) {
        return keccak256(abi.encode(target, selector));
    }

    /// @dev The call's selector is the first 4 bytes of its calldata; a value transfer (data < 4 bytes) is
    ///      treated as the `0x00000000` selector.
    function _selector(bytes memory data) private pure returns (bytes4 s) {
        if (data.length >= 4) {
            assembly {
                s := mload(add(data, 0x20))
            }
        }
    }
}
