// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IReentrancyGuard} from "@lattice/interfaces/security/IReentrancyGuard.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant REENTRANCY_GUARD_STORAGE_SLOT = 0xd4429f8db30ab6cbe40e0e5546854bc12f64b5d4a4cfb0ec3f5b16a895cd0c00;

/// @dev `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant REENTRANCY_GUARD_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x00000000 is `type(IReentrancyGuard).interfaceId` (interface has no functions, only an error).
/// `keccak256(abi.encode(bytes4(0x00000000), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IREENTRANCYGUARD_SLOT = 0xfb939cb1ca033f66389071014066e3ba51464fd8ec15c96518ea9663d9c0f494;

/// @dev Sentinel value indicating no active call. Using 1 instead of 0 saves gas on the
/// first call by avoiding a zero-to-nonzero SSTORE.
uint256 constant _NOT_ENTERED = 1;

/// @dev Sentinel value indicating an active (in-progress) call.
uint256 constant _ENTERED = 2;

/// @notice Storage struct for the ReentrancyGuard module.
/// @custom:storage-location erc7201:lattice.storage.ReentrancyGuard
struct ReentrancyGuardStorage {
    uint256 _status;
}

/// @title ReentrancyGuard Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol)
/// @notice Library providing reentrant call protection for Diamond facets.
/// @dev Use `nonReentrantBefore()` at the start and `nonReentrantAfter()` at the end of
/// guarded functions. The pair must always be called together.
library ReentrancyGuardLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                         REENTRANCY GUARD STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the storage struct for ReentrancyGuard at its ERC-7201 slot.
    function reentrancyGuardStorage() internal pure returns (ReentrancyGuardStorage storage $) {
        assembly {
            $.slot := REENTRANCY_GUARD_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IReentrancyGuard interface via ERC-165.
    /// @dev Writes `true` to the precomputed ERC-165 map slot.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IREENTRANCYGUARD_SLOT, true)
        }
    }

    /// @notice Initializes the ReentrancyGuard module.
    /// @dev Must be called between `InitializableLib.preInitializer` and `postInitializer`.
    /// Sets the reentrancy status to `_NOT_ENTERED` and registers the interface for ERC-165.
    function __ReentrancyGuard_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        reentrancyGuardStorage()._status = _NOT_ENTERED;
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          REENTRANCY GUARD OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Asserts that no reentrant call is in progress, then locks.
    /// @dev Call at the start of a guarded function. Must be paired with `nonReentrantAfter`.
    /// Reverts with `ReentrancyGuardReentrantCall` if reentrancy is detected.
    function nonReentrantBefore() internal {
        ReentrancyGuardStorage storage $ = reentrancyGuardStorage();
        if ($._status == _ENTERED) {
            revert IReentrancyGuard.ReentrancyGuardReentrantCall();
        }
        $._status = _ENTERED;
    }

    /// @notice Resets the reentrancy lock.
    /// @dev Call at the end of a guarded function. Must be paired with `nonReentrantBefore`.
    function nonReentrantAfter() internal {
        reentrancyGuardStorage()._status = _NOT_ENTERED;
    }

    /// @notice Combined guard: asserts non-reentrancy, executes inline, then resets.
    /// @dev Convenience wrapper. Prefer using `nonReentrantBefore`/`nonReentrantAfter` directly
    /// in functions that need explicit control over the lock lifetime.
    /// @param fn A no-argument function to execute between the lock and unlock.
    function nonReentrant(function() internal fn) internal {
        nonReentrantBefore();
        fn();
        nonReentrantAfter();
    }

    /// @notice Returns `true` when a nonReentrant call is currently executing.
    /// @dev Equivalent to OZ v5.1.0 `_reentrancyGuardEntered()`. Useful for `view` helpers
    /// that must behave differently when called mid-execution inside a guarded function.
    function reentrancyGuardEntered() internal view returns (bool) {
        return reentrancyGuardStorage()._status == _ENTERED;
    }
}
