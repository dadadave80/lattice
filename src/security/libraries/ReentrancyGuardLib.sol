// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev Solady's transient guard slot: `uint32(bytes4(keccak256("Reentrancy()"))) | 1 << 71`.
/// 9 bytes is large enough to avoid collisions in practice, but not too large to result in
/// excessive bytecode bloat. Lattice keeps its OZ-style `ReentrancyGuardReentrantCall` error, so
/// the revert paths mstore that selector explicitly instead of reusing the slot's low bytes.
uint256 constant _REENTRANCY_GUARD_SLOT = 0x8000000000ab143c06;

/// @title ReentrancyGuard Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Solady (https://github.com/vectorized/solady/blob/main/src/utils/ReentrancyGuardTransient.sol)
/// @notice Reentrancy protection for Diamond facets — transient-storage variant.
/// @dev On Ethereum mainnet the lock lives in transient storage (`TSTORE`/`TLOAD`, auto-cleared per
/// transaction); on every other chain it uses a regular `SSTORE` guard for widespread L2/EVM
/// compatibility (only mainnet is expensive anyway — Solady's default behavior). Diverges from
/// upstream: the virtual `_useTransientReentrancyGuardOnlyOnMainnet()` hook is dropped (library
/// functions cannot see contract-level overrides — the default is baked in), and the revert error is
/// Lattice's existing `ReentrancyGuardReentrantCall()`.
///
/// Call `entry()` at the start and `exit()` at the end of a guarded function — or inherit the
/// {ReentrancyGuard} mixin and use its `nonReentrant`/`nonReadReentrant` modifiers.
library ReentrancyGuardLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                          REENTRANCY GUARD OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Asserts that no reentrant call is in progress, then takes the lock.
    /// @dev Call at the start of a guarded function; must be paired with `exit()`.
    /// Reverts with `ReentrancyGuardReentrantCall` if the lock is already held.
    function entry() internal {
        uint256 s = _REENTRANCY_GUARD_SLOT;
        if (block.chainid == 1) {
            assembly ("memory-safe") {
                if tload(s) {
                    mstore(0x00, 0x3ee5aeb5) // `ReentrancyGuardReentrantCall()`.
                    revert(0x1c, 0x04)
                }
                tstore(s, address())
            }
        } else {
            assembly ("memory-safe") {
                if eq(sload(s), address()) {
                    mstore(0x00, 0x3ee5aeb5) // `ReentrancyGuardReentrantCall()`.
                    revert(0x1c, 0x04)
                }
                sstore(s, address())
            }
        }
    }

    /// @notice Releases the lock taken by `entry()`.
    /// @dev Call at the end of a guarded function; must be paired with `entry()`.
    /// On non-mainnet chains the slot is reset to a non-zero sentinel (the slot value itself)
    /// rather than zero, avoiding a fresh zero-to-nonzero `SSTORE` on the next entry.
    function exit() internal {
        uint256 s = _REENTRANCY_GUARD_SLOT;
        if (block.chainid == 1) {
            assembly ("memory-safe") {
                tstore(s, 0)
            }
        } else {
            assembly ("memory-safe") {
                sstore(s, s)
            }
        }
    }

    /// @notice Asserts that no reentrant call is in progress WITHOUT taking the lock.
    /// @dev Guards view functions against read-only reentrancy (a guarded write path calling back
    /// into a view mid-lock). Reverts with `ReentrancyGuardReentrantCall` if the lock is held.
    function check() internal view {
        uint256 s = _REENTRANCY_GUARD_SLOT;
        if (block.chainid == 1) {
            assembly ("memory-safe") {
                if tload(s) {
                    mstore(0x00, 0x3ee5aeb5) // `ReentrancyGuardReentrantCall()`.
                    revert(0x1c, 0x04)
                }
            }
        } else {
            assembly ("memory-safe") {
                if eq(sload(s), address()) {
                    mstore(0x00, 0x3ee5aeb5) // `ReentrancyGuardReentrantCall()`.
                    revert(0x1c, 0x04)
                }
            }
        }
    }

    /// @notice Asserts that no reentrant call is in progress, then locks.
    /// @dev Alias for `entry()`, kept for existing callers. Prefer the {ReentrancyGuard}
    /// `nonReentrant` modifier or `entry()`/`exit()` in new code.
    function nonReentrantBefore() internal {
        entry();
    }

    /// @notice Resets the reentrancy lock.
    /// @dev Alias for `exit()`, kept for existing callers.
    function nonReentrantAfter() internal {
        exit();
    }

    /// @notice Returns `true` when a guarded call is currently executing.
    /// @dev Equivalent to OZ v5.1.0 `_reentrancyGuardEntered()`. Useful for `view` helpers
    /// that must behave differently when called mid-execution inside a guarded function.
    function reentrancyGuardEntered() internal view returns (bool entered_) {
        uint256 s = _REENTRANCY_GUARD_SLOT;
        if (block.chainid == 1) {
            assembly ("memory-safe") {
                entered_ := iszero(iszero(tload(s)))
            }
        } else {
            assembly ("memory-safe") {
                entered_ := eq(sload(s), address())
            }
        }
    }
}
