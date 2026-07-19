// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {INonces} from "@lattice/interfaces/utils/INonces.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.Nonces")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant NONCES_STORAGE_SLOT = 0x2b93a5a8782d382c0f6890e7e2d77ba67ed77675c16cc334b45b931317d4de00;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant NONCES_ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x7ecebe00 is `type(INonces).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x7ecebe00), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_INONCES_SLOT = 0x7a551986b45870996296121343257817091920bfbe333333c5198eab95eb2fa2;

/// @notice Storage struct for Nonces module.
/// @custom:storage-location erc7201:lattice.storage.Nonces
struct NoncesStorage {
    mapping(address account => uint256) _nonces;
}

/// @title NoncesLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Nonces.sol)
/// @notice Library for tracking per-account nonces used in replay-protection schemes.
library NoncesLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function noncesStorage() internal pure returns (NoncesStorage storage $) {
        assembly {
            $.slot := NONCES_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the Nonces module.
    /// @dev Must be called inside a pre/postInitializer block.
    ///      Registers the INonces interface for ERC-165 discovery.
    function __Nonces_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the INonces interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_INONCES_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            NONCE OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the current nonce for the given owner.
    /// @param owner The address to query.
    /// @return The current nonce.
    function nonces(address owner) internal view returns (uint256) {
        NoncesStorage storage $ = noncesStorage();
        return $._nonces[owner];
    }

    /// @notice Returns the current nonce for the caller and increments it.
    /// @dev Does not check the nonce value; use `useCheckedNonce` for validated increments.
    /// @param owner The address whose nonce to consume.
    /// @return current The nonce value before incrementing.
    function useNonce(address owner) internal returns (uint256 current) {
        NoncesStorage storage $ = noncesStorage();
        current = $._nonces[owner];
        unchecked {
            $._nonces[owner] = current + 1;
        }
    }

    /// @notice Consumes a nonce after verifying it matches the expected value.
    /// @dev Reverts with {InvalidAccountNonce} if `nonce` does not equal the current nonce.
    /// @param owner The account whose nonce to consume.
    /// @param nonce The expected current nonce value.
    function useCheckedNonce(address owner, uint256 nonce) internal {
        uint256 current = useNonce(owner);
        if (current != nonce) {
            revert INonces.InvalidAccountNonce(owner, current);
        }
    }
}
