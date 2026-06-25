// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ISessionKey
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Admin/read surface of the `SessionKey` facet — scoped, expiring secondary keys that can authorize
///         batches through the ERC-7821 executor's signed-`opData` path without holding the owner key.
/// @dev A session key is an ECDSA EOA registered by an admin with a validity window and a `(target, selector)`
///      allowlist. `ANY_TARGET` (`address(type(uint160).max)`) and `ANY_SELECTOR` (`bytes4(0xffffffff)`) are
///      wildcards. A call's selector is the first 4 bytes of its calldata, or `0x00000000` for a plain
///      value transfer. Spend limits are a planned follow-on (not enforced in v1).
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

    /// @notice The key is the zero address or the `ANY_TARGET` sentinel.
    error InvalidSessionKey();

    /// @notice `validUntil` is in the past or not after `validAfter`.
    error InvalidExpiry();

    /// @notice The session key is unregistered, revoked, or outside its validity window.
    error SessionKeyNotActive(address key);

    /// @notice The session key is not permitted to call `(target, selector)`.
    error CallNotPermitted(address key, address target, bytes4 selector);

    /// @notice Registers (or replaces) a session key with a validity window + a `(target, selector)` allowlist.
    /// @dev Admin only. Re-registering overwrites the validity window and adds the given permissions.
    function registerSessionKey(address key, uint48 validAfter, uint48 validUntil, Permission[] calldata permissions)
        external;

    /// @notice Revokes a session key (clears its validity window). Admin only.
    function revokeSessionKey(address key) external;

    /// @notice Whether `key` is registered and currently within its validity window.
    function isSessionKeyActive(address key) external view returns (bool);

    /// @notice The validity window of `key` (`validUntil == 0` means unregistered/revoked).
    function sessionKeyValidity(address key) external view returns (uint48 validAfter, uint48 validUntil);

    /// @notice Whether `key` is permitted to call `(target, selector)` (honoring wildcards).
    function isCallPermitted(address key, address target, bytes4 selector) external view returns (bool);
}
