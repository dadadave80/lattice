// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ISessionKey
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Admin/read surface of the `SessionKey` facet — scoped, expiring secondary keys that can authorize
///         batches through the ERC-7821 executor's signed-`opData` path without holding the owner key.
/// @dev A session key is an ECDSA EOA registered by an admin with a validity window and a `(target, selector)`
///      allowlist. `ANY_TARGET` (`address(type(uint160).max)`) and `ANY_SELECTOR` (`bytes4(0xffffffff)`) are
///      wildcards, except that `ANY_TARGET` never matches the account itself: a self-call (a nested `execute`,
///      an admin entrypoint) needs a grant that names the account as its target. A call's selector is the first
///      4 bytes of its calldata, or `0x00000000` for a plain value transfer. Optional per-token spend limits cap
///      how much a key may move: a batch is charged the larger of its direct transfers (native value under the
///      token sentinel `0xEee…EEeE`, ERC-20 `transfer` and `transferFrom`-from-self) and the account's actual
///      balance decrease, which covers indirect spends such as a router pulling tokens. Any `approve` /
///      `increaseAllowance` a batch makes directly on a capped token is reset to 0 after the batch and verified
///      through `allowance`, and a key may not set a Permit2 allowance or a `setApprovalForAll` operator over a
///      capped token. Caps are meant for ERC-20s and native value: an `approve` on a capped ERC-721 fails
///      closed. A token with no configured limit is uncapped.
interface ISessionKey {
    /// @notice One `(target, selector)` permission grant; either field may be a wildcard sentinel.
    struct Permission {
        address target;
        bytes4 selector;
    }

    /// @notice Emitted when a session key is registered (or re-registered).
    event SessionKeyRegistered(address indexed key, uint48 validAfter, uint48 validUntil, uint256 permissions);

    /// @notice Emitted when a session key is revoked.
    event SessionKeyRevoked(address indexed key);

    /// @notice Emitted when a per-token spend cap is set (spent counter reset to 0).
    event SpendLimitSet(address indexed key, address indexed token, uint256 cap);

    /// @notice The key is the zero address or the `ANY_TARGET` sentinel.
    error InvalidSessionKey();

    /// @notice `validUntil` is in the past or not after `validAfter`.
    error InvalidExpiry();

    /// @notice The session key is unregistered, revoked, or outside its validity window.
    error SessionKeyNotActive(address key);

    /// @notice The session key is not permitted to call `(target, selector)`.
    error CallNotPermitted(address key, address target, bytes4 selector);

    /// @notice The batch would push the key's cumulative spend of `token` past its cap.
    error SpendLimitExceeded(address key, address token, uint256 cap, uint256 attempted);

    /// @notice The key has a spend cap on `token`, so it may not set a Permit2 allowance or an operator approval
    ///         (`selector`) over it.
    error ApprovalNotPermitted(address key, address token, bytes4 selector);

    /// @notice The post-batch `approve(spender, 0)` reset on a capped `token` reverted, returned `false`, or left
    ///         `allowance(account, spender)` unreadable or non-zero.
    error ApprovalResetFailed(address token, address spender);

    /// @notice Registers (or replaces) a session key with a validity window + a `(target, selector)` allowlist.
    /// @dev Admin only. Re-registering a key that was not revoked overwrites the validity window and adds the
    ///      given permissions to its existing ones. After {revokeSessionKey}, a registration starts clean.
    function registerSessionKey(address key, uint48 validAfter, uint48 validUntil, Permission[] calldata permissions)
        external;

    /// @notice Revokes a session key. Admin only.
    /// @dev Clears the validity window, invalidates every permission granted so far, and deletes the key's spend
    ///      caps and spent counters. Re-registering the key restores none of them; set its limits again.
    function revokeSessionKey(address key) external;

    /// @notice Whether `key` is registered and currently within its validity window.
    function isSessionKeyActive(address key) external view returns (bool);

    /// @notice The validity window of `key` (`validUntil == 0` means unregistered/revoked).
    function sessionKeyValidity(address key) external view returns (uint48 validAfter, uint48 validUntil);

    /// @notice Whether `key` is permitted to call `(target, selector)` (honoring wildcards; `ANY_TARGET` does not
    ///         match the account itself).
    function isCallPermitted(address key, address target, bytes4 selector) external view returns (bool);

    /// @notice Sets a cumulative spend cap for `key` on `token` (native sentinel `0xEee…EEeE`), resetting the
    ///         spent counter to 0. Admin only. A token with no cap set is uncapped.
    function setSpendLimit(address key, address token, uint256 cap) external;

    /// @notice The spend cap and amount already spent for `key` on `token`.
    function spendLimit(address key, address token) external view returns (uint256 cap, uint256 spent);
}
