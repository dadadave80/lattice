// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SessionKeyLib} from "@lattice/accounts/libraries/SessionKeyLib.sol";
import {ISessionKey} from "@lattice/interfaces/accounts/ISessionKey.sol";

/// @title SessionKey
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Session-key facet. An admin registers scoped, expiring secondary keys (a `(target, selector)`
///         allowlist + validity window); a registered key can then authorize batches through the
///         `ERC7821Executor` signed-`opData` path without holding the owner key.
/// @dev Stateless delegator — logic/storage live in {SessionKeyLib}. Enforces expiry, the allowlist (with
///      `ANY_*` wildcards) and per-token cumulative spend limits, with post-batch approval resets on capped
///      tokens. Revoking a key drops its grants and limits.
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

    /// @inheritdoc ISessionKey
    function setSpendLimit(address key, address token, uint256 cap) external virtual {
        SessionKeyLib.setSpendLimit(key, token, cap);
    }

    /// @inheritdoc ISessionKey
    function spendLimit(address key, address token) external view virtual returns (uint256 cap, uint256 spent) {
        return SessionKeyLib.spendLimit(key, token);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect SessionKey methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `isCallPermitted(address,address,bytes4)` 0xe4aea089
    ///      `isSessionKeyActive(address)` 0xf4d2a194
    ///      `registerSessionKey(address,uint48,uint48,(address,bytes4)[])` 0xc8337e5a
    ///      `revokeSessionKey(address)` 0x84f4fc6a
    ///      `sessionKeyValidity(address)` 0x78b6590d
    ///      `setSpendLimit(address,address,uint256)` 0xba9735cc
    ///      `spendLimit(address,address)` 0xab1c8674
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"e4aea089f4d2a194c8337e5a84f4fc6a78b6590dba9735ccab1c8674";
    }
}
