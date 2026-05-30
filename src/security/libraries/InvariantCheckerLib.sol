// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IInvariantChecker} from "@lattice/interfaces/IInvariantChecker.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.InvariantChecker")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant INVARIANT_CHECKER_STORAGE_SLOT = 0x6d7e4fbc04e31fa71f6fa52aa22270dd459ba0a3bd079c75a4fa29fd0ddbc200;

/// @dev `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant INVARIANT_CHECKER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x24e34e52 is `type(IInvariantChecker).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x24e34e52), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IINVARIANTCHECKER_SLOT = 0x1aa8e25c37e7f12aeead6e76f9ac394d6db559f39dd1228f00e20ba394b198e1;

/// @notice An on-chain invariant: a target contract and function selector to staticcall.
struct Invariant {
    address target;
    bytes4 selector;
}

/// @notice Top-level storage struct for the InvariantChecker module.
/// @custom:storage-location erc7201:lattice.storage.InvariantChecker
struct InvariantCheckerStorage {
    mapping(bytes32 key => Invariant) _invariants;
}

/// @title InvariantChecker Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing a registry of named on-chain invariants for Diamond facets.
/// @dev Admin registers (key → target + selector) pairs. Anyone can call `checkInvariant`
///      to staticcall the target and verify the bool return value. The check reverts on
///      false return or on a failed staticcall.
library InvariantCheckerLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                        INVARIANT CHECKER STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the storage struct for InvariantChecker at its ERC-7201 slot.
    function invariantCheckerStorage() internal pure returns (InvariantCheckerStorage storage $) {
        assembly {
            $.slot := INVARIANT_CHECKER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IInvariantChecker interface via ERC-165.
    /// @dev Writes `true` to the precomputed ERC-165 map slot.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IINVARIANTCHECKER_SLOT, true)
        }
    }

    /// @notice Initializes the InvariantChecker module.
    /// @dev Must be called between `InitializableLib.preInitializer` and `postInitializer`.
    ///      Registers the IInvariantChecker interface ID for ERC-165 discovery.
    function __InvariantChecker_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       INVARIANT CHECKER OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers or updates an invariant.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Reverts if `target == address(0)`.
    ///      Emits `InvariantRegistered`.
    /// @param key      The invariant key.
    /// @param target   The contract address to call (must not be address(0)).
    /// @param selector The function selector to invoke (must return a bool).
    function registerInvariant(bytes32 key, address target, bytes4 selector) internal {
        AccessControlLib.checkRole(0x00);
        _registerInvariant(key, target, selector);
    }

    /// @notice Removes a registered invariant.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Emits `InvariantUnregistered`.
    /// @param key The invariant key to remove.
    function unregisterInvariant(bytes32 key) internal {
        AccessControlLib.checkRole(0x00);
        _unregisterInvariant(key);
    }

    /// @notice Returns the target address and function selector registered for `key`.
    /// @param key The invariant key to query.
    /// @return target   The contract address to call.
    /// @return selector The function selector to invoke.
    function getInvariant(bytes32 key) internal view returns (address target, bytes4 selector) {
        Invariant storage inv = invariantCheckerStorage()._invariants[key];
        return (inv.target, inv.selector);
    }

    /// @notice Performs the staticcall check for `key` and reverts on violation or call failure.
    /// @dev Reverts with `InvariantNotRegistered` if the key is unregistered.
    ///      Reverts with `InvariantViolatedError` if the call returns false.
    ///      Reverts with `InvariantCheckFailed` if the staticcall itself reverts.
    /// @param key The invariant key to check.
    function checkInvariant(bytes32 key) internal view {
        _checkInvariant(key);
    }

    /// @notice Checks multiple invariants in order, reverting on the first failure.
    /// @param keys The array of invariant keys to check sequentially.
    function checkInvariants(bytes32[] calldata keys) internal view {
        uint256 len = keys.length;
        for (uint256 i = 0; i < len; ++i) {
            _checkInvariant(keys[i]);
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Internal — registers or updates an invariant entry.
    function _registerInvariant(bytes32 key, address target, bytes4 selector) internal {
        if (target == address(0)) revert IInvariantChecker.InvariantInvalidTarget();
        invariantCheckerStorage()._invariants[key] = Invariant({target: target, selector: selector});
        emit IInvariantChecker.InvariantRegistered(key, target, selector);
    }

    /// @notice Internal — removes an invariant entry.
    function _unregisterInvariant(bytes32 key) internal {
        delete invariantCheckerStorage()._invariants[key];
        emit IInvariantChecker.InvariantUnregistered(key);
    }

    /// @notice Internal — performs the staticcall and checks the bool return.
    function _checkInvariant(bytes32 key) internal view {
        Invariant storage inv = invariantCheckerStorage()._invariants[key];
        if (inv.target == address(0)) revert IInvariantChecker.InvariantNotRegistered(key);

        (bool success, bytes memory returnData) = inv.target.staticcall(abi.encodePacked(inv.selector));

        if (!success) revert IInvariantChecker.InvariantCheckFailed(key);

        // Decode bool — must be exactly 32 bytes (a well-formed ABI-encoded bool).
        if (returnData.length < 32) revert IInvariantChecker.InvariantCheckFailed(key);

        bool result = abi.decode(returnData, (bool));
        if (!result) {
            revert IInvariantChecker.InvariantViolatedError(key);
        }
    }
}
