// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SessionKeyLib} from "@lattice/accounts/libraries/SessionKeyLib.sol";
import {ISessionKey} from "@lattice/interfaces/ISessionKey.sol";

/// @title SessionKey
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Session-key facet. An admin registers scoped, expiring secondary keys (a `(target, selector)`
///         allowlist + validity window); a registered key can then authorize batches through the
///         `ERC7821Executor` signed-`opData` path without holding the owner key.
/// @dev Stateless delegator — logic/storage live in {SessionKeyLib}. v1 enforces expiry + the allowlist
///      (with `ANY_*` wildcards); per-token spend limits are a planned follow-on.
/// @custom:lattice-version 0.1.0
contract SessionKey is ISessionKey {
    /// @inheritdoc ISessionKey
    function registerSessionKey(address key, uint48 validAfter, uint48 validUntil, Permission[] calldata permissions)
        external
        virtual
    {
        SessionKeyLib.registerSessionKey(key, validAfter, validUntil, permissions);
    }

    /// @inheritdoc ISessionKey
    function revokeSessionKey(address key) external virtual {
        SessionKeyLib.revokeSessionKey(key);
    }

    /// @inheritdoc ISessionKey
    function isSessionKeyActive(address key) external view virtual returns (bool) {
        return SessionKeyLib.isSessionKeyActive(key);
    }

    /// @inheritdoc ISessionKey
    function sessionKeyValidity(address key) external view virtual returns (uint48 validAfter, uint48 validUntil) {
        return SessionKeyLib.sessionKeyValidity(key);
    }

    /// @inheritdoc ISessionKey
    function isCallPermitted(address key, address target, bytes4 selector) external view virtual returns (bool) {
        return SessionKeyLib.isCallPermitted(key, target, selector);
    }
}
