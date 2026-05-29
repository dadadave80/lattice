// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC20Capped} from "@lattice/interfaces/IERC20Capped.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC20Capped")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC20CAPPED_STORAGE_SLOT = 0xf3126bfe4af748db9eb069fa2ed04557107fb53a164b5206750073586b2bc900;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC20CAPPED_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x355274ea is `type(IERC20Capped).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x355274ea), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC20CAPPED_SLOT = 0xb2089445722e0a36969fff4735cd037fb1b56a44be61c7f6c752270db855a1b7;

/// @notice Storage struct for ERC-20Capped module.
/// @custom:storage-location erc7201:lattice.storage.ERC20Capped
struct ERC20CappedStorage {
    uint256 _cap;
}

/// @title ERC20CappedLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing a capped total supply for ERC-20 tokens.
library ERC20CappedLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc20CappedStorage() internal pure returns (ERC20CappedStorage storage $) {
        assembly {
            $.slot := ERC20CAPPED_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ERC-20Capped module with a supply cap.
    /// @dev Must be called inside a pre/postInitializer block.
    ///      Reverts with ERC20InvalidCap if cap is 0.
    function __ERC20Capped_init(uint256 cap_) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        if (cap_ == 0) revert IERC20Capped.ERC20InvalidCap(0);
        erc20CappedStorage()._cap = cap_;
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC20Capped interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC20CAPPED_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the cap on the token's total supply.
    function cap() internal view returns (uint256) {
        return erc20CappedStorage()._cap;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            CAP ENFORCEMENT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Reverts if `newSupply` would exceed the cap.
    /// @dev Call this before minting to enforce the cap constraint.
    function _checkCap(uint256 newSupply) internal view {
        uint256 cap_ = cap();
        if (newSupply > cap_) {
            revert IERC20Capped.ERC20ExceededCap(newSupply, cap_);
        }
    }
}
