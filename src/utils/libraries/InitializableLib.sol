// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                       CUSTOM ERRORS                        */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/// @dev The contract is already initialized.
error InvalidInitialization();

/// @dev The contract is not initializing.
error NotInitializing();

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                           EVENTS                           */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/// @dev Triggered when the contract has been initialized.
event Initialized(uint64 version);

/// @dev `keccak256(bytes("Initialized(uint64)"))`.
bytes32 constant _INITIALIZED_EVENT_SIGNATURE = 0xc7f505b2f371ae2175ee4913f4499e1f2633a7b5936321eed1cdaeb6115181d2;

/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
/*                          STORAGE                           */
/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

/// @dev The default initializable slot is given by:
/// `bytes32(~uint256(uint32(bytes4(keccak256("_INITIALIZABLE_SLOT")))))`.
///
/// Bits Layout:
/// - [0]     `initializing`
/// - [1..64] `initializedVersion`
bytes32 constant _INITIALIZABLE_SLOT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffbf601132;

/// @title InitializableLib
/// @author Vendored from diamond-lib v0.3.0
///         (https://github.com/dadadave80/diamond-lib/blob/v0.3.0/test/utils/InitializableLib.sol). Moved out of
///         upstream src/ in v0.3.0 ("initializables move to lattice"); the returns-slot preInitializer fixes
///         nested-constructor-initializer double-finalize — postInitializer MUST receive the RETURNED slot.
/// @notice Initialization guard logic for Lattice diamonds, facet inits, and standalones.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/Initializable.sol)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/tree/master/contracts/proxy/utils/Initializable.sol)
library InitializableLib {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         OPERATIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Returns the default initializable storage slot.
    function initializableSlot() internal pure returns (bytes32) {
        return _INITIALIZABLE_SLOT;
    }

    /// @dev Marks the start of an initializer-guarded function.
    ///
    /// Returns the slot to pass to `postInitializer`. In the nested
    /// constructor-initializer case the returned slot is zero, which tells
    /// `postInitializer` to skip finalization — the outermost initializer
    /// clears the flag and emits the event exactly once. Always pass the
    /// RETURNED value to `postInitializer`, not the original slot.
    function preInitializer(bytes32 _initializableSlot) internal returns (bytes32 slot_) {
        slot_ = _initializableSlot;
        assembly ("memory-safe") {
            // Storage Layout:
            // Bit 0:      initializing flag (1 = currently initializing, prevents reentrancy)
            // Bits 1-64:  initialized version (0 = never init, 1+ = initialized to version)

            let i := sload(slot_)

            // Set slot to 3 (binary: 11):
            // Bit 0 = 1 (initializing = true)
            // Bit 1 = 1 (version = 1)
            sstore(slot_, 3)

            // If i != 0, this means contract has previous initialization state
            if i {
                // Allow re-invocation only if:
                // 1. Contract has no code yet (being called from constructor)
                // 2. Previous version is exactly 1
                //
                // The condition iszero(lt(extcodesize(address()), eq(shr(1, i), 1)))
                // is logically: NOT(code.length == 0 AND version == 1)
                //
                // If true, revert with InvalidInitialization error
                if iszero(lt(extcodesize(address()), eq(shr(1, i), 1))) {
                    mstore(0x00, 0xf92ee8a9) // `InvalidInitialization()`.
                    revert(0x1c, 0x04)
                }

                // If the old initializing bit was set (nested call within a
                // constructor's initializer), zero out the returned slot so
                // `postInitializer` skips finalization.
                slot_ := shl(shl(255, i), slot_)
            }
        }
    }

    /// @dev Marks the end of an initializer-guarded function.
    /// Takes the slot RETURNED by `preInitializer`.
    function postInitializer(bytes32 _initializableSlot) internal {
        assembly ("memory-safe") {
            // Skip if `preInitializer` returned zero
            // (nested constructor initializer case)
            if _initializableSlot {
                // Set slot to 2 (binary: 10):
                // Bit 0 = 0 (initializing = false, reentrancy guard released)
                // Bit 1 = 1 (version = 1)
                sstore(_initializableSlot, 2)

                // Emit Initialized(1) event with version = 1
                mstore(0x20, 1)
                log1(0x20, 0x20, _INITIALIZED_EVENT_SIGNATURE)
            }
        }
    }

    /// @dev Marks the start of a reinitializer-guarded function.
    function preReinitializer(bytes32 _initializableSlot, uint64 _version) internal {
        assembly ("memory-safe") {
            // Clean upper bits, and shift left by 1 to make space for the initializing bit.
            _version := shl(1, and(_version, 0xffffffffffffffff))
            let i := sload(_initializableSlot)
            // If `initializing == 1 || initializedVersion >= version`.
            if iszero(lt(and(i, 1), lt(i, _version))) {
                mstore(0x00, 0xf92ee8a9) // `InvalidInitialization()`.
                revert(0x1c, 0x04)
            }
            // Set `initializing` to 1, `initializedVersion` to `version`.
            sstore(_initializableSlot, or(1, _version))
        }
    }

    /// @dev Marks the end of a reinitializer-guarded function.
    function postReinitializer(bytes32 _initializableSlot, uint64 _version) internal {
        assembly ("memory-safe") {
            // Clean upper bits, and shift left by 1 to match storage layout.
            _version := shl(1, and(_version, 0xffffffffffffffff))
            // Set `initializing` to 0, `initializedVersion` to `version`.
            sstore(_initializableSlot, _version)
            // Emit the {Initialized} event.
            mstore(0x20, shr(1, _version))
            log1(0x20, 0x20, _INITIALIZED_EVENT_SIGNATURE)
        }
    }

    /// @dev Reverts if the contract is not initializing.
    function checkInitializing(bytes32 _initializableSlot) internal view {
        assembly ("memory-safe") {
            if iszero(and(1, sload(_initializableSlot))) {
                mstore(0x00, 0xd7e6bcf8) // `NotInitializing()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Locks any future initializations by setting the initialized version to `2**64 - 1`.
    ///
    /// Calling this in the constructor will prevent the contract from being initialized
    /// or reinitialized. It is recommended to use this to lock implementation contracts
    /// that are designed to be called through proxies.
    ///
    /// Emits an {Initialized} event the first time it is successfully called.
    function disableInitializers(bytes32 _initializableSlot) internal {
        assembly ("memory-safe") {
            let i := sload(_initializableSlot)
            if and(i, 1) {
                mstore(0x00, 0xf92ee8a9) // `InvalidInitialization()`.
                revert(0x1c, 0x04)
            }
            let uint64max := 0xffffffffffffffff
            if iszero(eq(shr(1, i), uint64max)) {
                // Set `initializing` to 0, `initializedVersion` to `2**64 - 1`.
                sstore(_initializableSlot, shl(1, uint64max))
                // Emit the {Initialized} event.
                mstore(0x20, uint64max)
                log1(0x20, 0x20, _INITIALIZED_EVENT_SIGNATURE)
            }
        }
    }

    /// @dev Returns the highest version that has been initialized.
    function getInitializedVersion(bytes32 _initializableSlot) internal view returns (uint64 version_) {
        assembly ("memory-safe") {
            version_ := shr(1, sload(_initializableSlot))
        }
    }

    /// @dev Returns whether the contract is currently initializing.
    function isInitializing(bytes32 _initializableSlot) internal view returns (bool result_) {
        assembly ("memory-safe") {
            result_ := and(1, sload(_initializableSlot))
        }
    }
}
