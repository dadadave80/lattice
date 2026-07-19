// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC3156FlashBorrower} from "@lattice/interfaces/external/ercs/IERC3156FlashBorrower.sol";
import {IERC20FlashMint} from "@lattice/interfaces/tokens/IERC20FlashMint.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC20FLASHMINT_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0xe4143091 is `type(IERC3156FlashLender).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xe4143091), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC3156FLASHLENDER_SLOT =
    0x4275a6f3829c1d71af9909c7c48ca9008f7cc1253f2e37d9ec6b19b0ee746d41;

/// @dev Return value a borrower must echo from {IERC3156FlashBorrower-onFlashLoan}.
bytes32 constant ERC3156_CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

/// @title ERC20FlashMintLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20FlashMint.sol)
/// @notice Library implementing the ERC-3156 flash-mint extension for ERC-20. Adds no own storage.
/// @dev The token itself is the flash lender: principal is minted to the borrower for the duration of the call
///      and burned at the end, or the whole call reverts. The fee is fixed at 0 and the fee receiver at
///      `address(0)` (fee burned) — Lattice keeps all logic in the library, so OZ's `virtual` fee overrides are
///      not available; a fee-charging variant would be a separate library/configuration.
library ERC20FlashMintLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IERC3156FlashLender interface for ERC-165 discovery.
    /// @dev Must be called inside a pre/postInitializer block. No own storage to initialize.
    function __ERC20FlashMint_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    /// @notice Registers support for the IERC3156FlashLender interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC3156FLASHLENDER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               FLASH MECHANICS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The maximum loan available: the whole remaining uint256 headroom of the supply, or 0 for other tokens.
    function maxFlashLoan(address token) internal view returns (uint256) {
        return token == address(this) ? type(uint256).max - ERC20Lib.totalSupply() : 0;
    }

    /// @notice The fee charged for a flash loan — always 0 here; reverts for an unsupported token.
    function flashFee(
        address token,
        uint256 /*value*/
    )
        internal
        view
        returns (uint256)
    {
        if (token != address(this)) revert IERC20FlashMint.ERC3156UnsupportedToken(token);
        return 0;
    }

    /// @notice Performs a flash loan: mint `value` to `receiver`, run the callback, then pull back and burn it.
    /// @dev Reenters safely: the minted amount is always recovered and burned by the end, or the call reverts.
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 value, bytes calldata data)
        internal
        returns (bool)
    {
        uint256 maxLoan = maxFlashLoan(token);
        if (value > maxLoan) revert IERC20FlashMint.ERC3156ExceededMaxLoan(maxLoan);
        uint256 fee = flashFee(token, value);
        ERC20Lib._mint(address(receiver), value);
        if (receiver.onFlashLoan(msg.sender, token, value, fee, data) != ERC3156_CALLBACK_SUCCESS) {
            revert IERC20FlashMint.ERC3156InvalidReceiver(address(receiver));
        }
        ERC20Lib._spendAllowance(address(receiver), address(this), value + fee);
        ERC20Lib._burn(address(receiver), value + fee); // fee == 0 and fee receiver is address(0) => burn all
        return true;
    }
}
