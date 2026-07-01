// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

/// @title ERC20Pausable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Pausable.sol)
/// @notice Stateless Diamond facet — ERC-20 whose token transfers can be paused.
/// @dev Reuses the shared {PausableLib} pause state (no new storage/interface): the diamond also cuts in the
///      {Pausable} facet for the admin-gated `pause()`/`unpause()` control. OZ gates the `_update` hook (transfer,
///      mint and burn); Lattice's base {ERC20} facet calls {ERC20Lib} directly with no facet-level `_update`, so the
///      gate is applied to the public movement surface (`transfer`/`transferFrom`). A composing facet that also
///      mints/burns while paused should apply {PausableLib.whenNotPaused} on those entrypoints too.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC20Pausable {
    /// @notice Moves `value` to `to`, reverting with {IPausable-EnforcedPause} while paused (replaces base transfer).
    function transfer(address to, uint256 value) public virtual returns (bool) {
        PausableLib.whenNotPaused();
        return ERC20Lib.transfer(to, value);
    }

    /// @notice Moves `value` from `from` to `to`, reverting with {IPausable-EnforcedPause} while paused (replaces base).
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        PausableLib.whenNotPaused();
        return ERC20Lib.transferFrom(from, to, value);
    }
}
