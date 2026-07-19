// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.Pausable")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant PAUSABLE_STORAGE_SLOT = 0x1484a55ae2f6de193138ed7f3a9f9b3307c3701783002d2a375beb8271f96200;

/// @dev 0xe78a39d8 is `type(IPausable).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xe78a39d8), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IPAUSABLE_SLOT = 0xad8c21edea54b0e7ec01d18544e806e752f64eb497d475cd8353c0c8726b4d3d;

/// @notice Storage struct for the Pausable module.
/// @custom:storage-location erc7201:lattice.storage.Pausable
struct PausableStorage {
    bool _paused;
}

/// @title Pausable Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Pausable.sol)
/// @notice Library implementing pausable lifecycle control for Diamond facets.
/// @dev Pause/unpause is restricted to the DEFAULT_ADMIN_ROLE via AccessControlLib.
library PausableLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                             PAUSABLE STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the storage struct for Pausable at its ERC-7201 slot.
    function pausableStorage() internal pure returns (PausableStorage storage $) {
        assembly {
            $.slot := PAUSABLE_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IPausable interface via ERC-165.
    /// @dev Writes `true` to the precomputed ERC-165 map slot.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IPAUSABLE_SLOT, true)
        }
    }

    /// @notice Initializes the Pausable module — ERC-165 registration only.
    /// @dev Must be called inside an `initializer`-guarded function (see {Initializable}); compose it
    /// from any diamond init that cuts {Pausable} — there is no dedicated init contract. `_paused`
    /// needs no seeding (false is the zero default). Deliberate divergence from OZ (which registers
    /// nothing): diamonds rely on ERC-165 discovery, so the IPausable interfaceId is registered here.
    function __Pausable_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             PAUSABLE OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns whether the contract is currently paused.
    /// @return bool True if paused, false otherwise.
    function paused() internal view returns (bool) {
        return pausableStorage()._paused;
    }

    /// @notice Reverts if the contract is paused.
    /// @dev Use at the start of functions that must not execute while paused — or inherit the
    /// {Pausable} facade and use its `whenNotPaused` modifier.
    function checkNotPaused() internal view {
        if (paused()) revert IPausable.EnforcedPause();
    }

    /// @notice Reverts if the contract is NOT paused.
    /// @dev Use in functions that require the contract to be paused — or inherit the {Pausable}
    /// facade and use its `whenPaused` modifier.
    function checkPaused() internal view {
        if (!paused()) revert IPausable.ExpectedPause();
    }

    /// @notice Pauses the contract.
    /// @dev Requires the caller to hold DEFAULT_ADMIN_ROLE. Reverts with `EnforcedPause` if already paused.
    /// Emits {Paused} event.
    function pause() internal {
        AccessControlLib.checkRole(0x00);
        checkNotPaused();
        _pause();
    }

    /// @notice Unpauses the contract.
    /// @dev Requires the caller to hold DEFAULT_ADMIN_ROLE. Reverts with `ExpectedPause` if not paused.
    /// Emits {Unpaused} event.
    function unpause() internal {
        AccessControlLib.checkRole(0x00);
        checkPaused();
        _unpause();
    }

    /// @notice Raw pause — sets paused state to true and emits `Paused`.
    /// @dev No auth check; callers must enforce authorization before calling this.
    function _pause() internal {
        pausableStorage()._paused = true;
        emit IPausable.Paused(msg.sender);
    }

    /// @notice Raw unpause — sets paused state to false and emits `Unpaused`.
    /// @dev No auth check; callers must enforce authorization before calling this.
    function _unpause() internal {
        pausableStorage()._paused = false;
        emit IPausable.Unpaused(msg.sender);
    }
}
