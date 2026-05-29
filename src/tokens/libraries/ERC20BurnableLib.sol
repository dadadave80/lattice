// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {ERC20Lib} from "@lattice/tokens/libraries/ERC20Lib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC20BURNABLE_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x3b5a0bf8 is `type(IERC20Burnable).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x3b5a0bf8), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC20BURNABLE_SLOT = 0x20898a14bb56c69b48cb37845539190e2348a67664163cad45eb1e5d40d06096;

/// @title ERC20BurnableLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing ERC-20 burn extensions. Adds no own storage.
/// @dev Known limitation (IMP-1): OZ marks `_spendAllowance` as `virtual` to allow
///      downstream extensions (e.g., Permit-based overrides) to intercept allowance
///      consumption. Solidity libraries cannot declare `virtual` functions, so
///      `burnFrom` is hardwired to `ERC20Lib._spendAllowance`. If permit-based
///      allowance overriding is required in the future, an `_inner` delegate pattern
///      or a hook in `ERC20Lib` will be needed to restore the override chain.
library ERC20BurnableLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IERC20Burnable interface for ERC-165 discovery.
    /// @dev Must be called inside a pre/postInitializer block. No own storage to initialize.
    function __ERC20Burnable_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC20Burnable interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC20BURNABLE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             BURN OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Destroys `value` tokens from the caller's balance.
    function burn(uint256 value) internal {
        ERC20Lib._burn(ContextLib.msgSender(), value);
    }

    /// @notice Destroys `value` tokens from `account`, using the caller's allowance.
    function burnFrom(address account, uint256 value) internal {
        ERC20Lib._spendAllowance(account, ContextLib.msgSender(), value);
        ERC20Lib._burn(account, value);
    }
}
