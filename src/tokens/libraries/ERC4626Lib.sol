// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {ERC20Lib} from "@lattice/tokens/libraries/ERC20Lib.sol";
import {IERC20} from "@lattice/interfaces/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/IERC4626.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC4626")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC4626_STORAGE_SLOT = 0x748f49bc653df23655f3b413e3d5c91c1b4c965af17a32d743e995b145325100;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC4626_ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x87dfe5a0 is `type(IERC4626).interfaceId` (XOR of vault-specific function selectors only; inherited IERC20 excluded).
/// `keccak256(abi.encode(bytes4(0x87dfe5a0), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC4626_SLOT = 0xdad016fc8af4f826152a6bfdd6ece63fb81a66a94f522cc8a79db8d6838e2732;

/// @notice Storage struct for ERC-4626 module.
/// @custom:storage-location erc7201:lattice.storage.ERC4626
struct ERC4626Storage {
    address _asset;
    uint8 _underlyingDecimals;
    uint8 _decimalsOffset;
}

/// @notice Rounding direction for mulDiv calculations.
enum Rounding {
    Floor,
    Ceil
}

/// @title ERC4626Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing the ERC-4626 Tokenized Vault Standard.
/// @dev Mirrors OpenZeppelin v5 ERC4626 logic. All state lives in an ERC-7201 slot.
///      The vault IS an ERC-20 share token — callers must also initialize ERC20Lib.
library ERC4626Lib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc4626Storage() internal pure returns (ERC4626Storage storage $) {
        assembly {
            $.slot := ERC4626_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ERC-4626 module with an underlying asset and virtual share offset.
    /// @dev Must be called inside a pre/postInitializer block, after ERC20Lib.__ERC20_init.
    /// @param asset_ The underlying ERC-20 token address.
    /// @param decimalsOffset_ Virtual share decimals offset for inflation-attack mitigation (usually 0).
    function __ERC4626_init(address asset_, uint8 decimalsOffset_) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);

        ERC4626Storage storage $ = erc4626Storage();
        $._asset = asset_;
        $._decimalsOffset = decimalsOffset_;

        // Try to fetch underlying decimals; default to 18 on failure.
        uint8 underlyingDecimals_ = 18;
        try IERC20Metadata(asset_).decimals() returns (uint8 d) {
            underlyingDecimals_ = d;
        } catch {}
        $._underlyingDecimals = underlyingDecimals_;

        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC4626 interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC4626_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the underlying asset address.
    function asset() internal view returns (address) {
        return erc4626Storage()._asset;
    }

    /// @notice Returns the vault's decimals: underlying decimals + offset.
    function decimals() internal view returns (uint8) {
        ERC4626Storage storage $ = erc4626Storage();
        return $._underlyingDecimals + $._decimalsOffset;
    }

    /// @notice Returns total underlying assets held by the vault (default: balance of this contract).
    function totalAssets() internal view returns (uint256) {
        return IERC20(erc4626Storage()._asset).balanceOf(address(this));
    }

    /// @notice Returns shares equivalent to `assets` (floor rounding).
    function convertToShares(uint256 assets) internal view returns (uint256) {
        return _convertToShares(assets, Rounding.Floor);
    }

    /// @notice Returns assets equivalent to `shares` (floor rounding).
    function convertToAssets(uint256 shares) internal view returns (uint256) {
        return _convertToAssets(shares, Rounding.Floor);
    }

    /// @notice Returns the maximum depositible assets for `receiver` (unbounded by default).
    function maxDeposit(address) internal pure returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Returns the maximum mintable shares for `receiver` (unbounded by default).
    function maxMint(address) internal pure returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Returns the maximum withdrawable assets for `owner`.
    function maxWithdraw(address owner) internal view returns (uint256) {
        return _convertToAssets(ERC20Lib.balanceOf(owner), Rounding.Floor);
    }

    /// @notice Returns the maximum redeemable shares for `owner`.
    function maxRedeem(address owner) internal view returns (uint256) {
        return ERC20Lib.balanceOf(owner);
    }

    /// @notice Simulates shares minted for a `deposit` of `assets` (floor rounding).
    function previewDeposit(uint256 assets) internal view returns (uint256) {
        return _convertToShares(assets, Rounding.Floor);
    }

    /// @notice Simulates assets required to `mint` exactly `shares` (ceiling rounding).
    function previewMint(uint256 shares) internal view returns (uint256) {
        return _convertToAssets(shares, Rounding.Ceil);
    }

    /// @notice Simulates shares burned for a `withdraw` of `assets` (ceiling rounding).
    function previewWithdraw(uint256 assets) internal view returns (uint256) {
        return _convertToShares(assets, Rounding.Ceil);
    }

    /// @notice Simulates assets returned for redeeming `shares` (floor rounding).
    function previewRedeem(uint256 shares) internal view returns (uint256) {
        return _convertToAssets(shares, Rounding.Floor);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Deposits `assets` and mints shares to `receiver`.
    function deposit(uint256 assets, address receiver) internal returns (uint256 shares) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert IERC4626.ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }
        shares = previewDeposit(assets);
        _deposit(ContextLib.msgSender(), receiver, assets, shares);
    }

    /// @notice Mints exactly `shares` to `receiver`, pulling the required assets.
    function mint(uint256 shares, address receiver) internal returns (uint256 assets) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert IERC4626.ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }
        assets = previewMint(shares);
        _deposit(ContextLib.msgSender(), receiver, assets, shares);
    }

    /// @notice Withdraws `assets` from the vault, burning the required shares from `owner`.
    function withdraw(uint256 assets, address receiver, address owner) internal returns (uint256 shares) {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert IERC4626.ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }
        shares = previewWithdraw(assets);
        _withdraw(ContextLib.msgSender(), receiver, owner, assets, shares);
    }

    /// @notice Redeems `shares` from `owner`, transferring assets to `receiver`.
    function redeem(uint256 shares, address receiver, address owner) internal returns (uint256 assets) {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert IERC4626.ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }
        assets = previewRedeem(shares);
        _withdraw(ContextLib.msgSender(), receiver, owner, assets, shares);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Converts `assets` to shares using the given rounding direction.
    ///      Formula: assets * (totalSupply + 10**offset) / (totalAssets + 1)
    function _convertToShares(uint256 assets, Rounding rounding) internal view returns (uint256) {
        ERC4626Storage storage $ = erc4626Storage();
        uint256 totalSupply_ = ERC20Lib.totalSupply();
        uint256 totalAssets_ = totalAssets();
        uint256 virtualShares = totalSupply_ + (10 ** uint256($._decimalsOffset));
        uint256 virtualAssets = totalAssets_ + 1;
        return mulDiv(assets, virtualShares, virtualAssets, rounding);
    }

    /// @dev Converts `shares` to assets using the given rounding direction.
    ///      Formula: shares * (totalAssets + 1) / (totalSupply + 10**offset)
    function _convertToAssets(uint256 shares, Rounding rounding) internal view returns (uint256) {
        ERC4626Storage storage $ = erc4626Storage();
        uint256 totalSupply_ = ERC20Lib.totalSupply();
        uint256 totalAssets_ = totalAssets();
        uint256 virtualShares = totalSupply_ + (10 ** uint256($._decimalsOffset));
        uint256 virtualAssets = totalAssets_ + 1;
        return mulDiv(shares, virtualAssets, virtualShares, rounding);
    }

    /// @dev Transfers assets in, mints shares, emits Deposit.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal {
        address asset_ = erc4626Storage()._asset;
        _safeTransferFrom(asset_, caller, address(this), assets);
        ERC20Lib._mint(receiver, shares);
        emit IERC4626.Deposit(caller, receiver, assets, shares);
    }

    /// @dev Spends allowance if needed, burns shares, transfers assets out, emits Withdraw.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal {
        if (caller != owner) {
            ERC20Lib._spendAllowance(owner, caller, shares);
        }
        ERC20Lib._burn(owner, shares);
        _safeTransfer(erc4626Storage()._asset, receiver, assets);
        emit IERC4626.Withdraw(caller, receiver, owner, assets, shares);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         SAFE TRANSFER HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Calls `token.transfer(to, amount)` and reverts with SafeERC20FailedOperation if it fails or
    ///      returns false. Handles tokens that do not return a bool (e.g. USDT).
    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        if (!ok || (ret.length > 0 && !abi.decode(ret, (bool)))) {
            revert IERC4626.SafeERC20FailedOperation(token);
        }
    }

    /// @dev Calls `token.transferFrom(from, to, amount)` and reverts with SafeERC20FailedOperation if it
    ///      fails or returns false. Handles tokens that do not return a bool (e.g. USDT).
    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        if (!ok || (ret.length > 0 && !abi.decode(ret, (bool)))) {
            revert IERC4626.SafeERC20FailedOperation(token);
        }
    }

    // Ported from OpenZeppelin Math.mulDiv v5.1.0
    /// @dev Calculates x * y / denominator with full 512-bit precision (Remco Bloemen algorithm).
    ///      Reverts with MathOverflowedMulDiv if the result overflows a uint256 or the denominator is 0.
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2²⁵⁶ and mod 2²⁵⁶ - 1, then use
            // the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2²⁵⁶ + prod0.
            uint256 prod0 = x * y; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return prod0 / denominator;
            }

            // Make sure the result is less than 2²⁵⁶. Also prevents denominator == 0.
            if (denominator <= prod1) {
                revert IERC4626.MathOverflowedMulDiv();
            }

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator.
            // Always >= 1. See https://cs.stackexchange.com/q/138556/92363.

            uint256 twos = denominator & (0 - denominator);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2²⁵⁶ / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2²⁵⁶. Now that denominator is an odd number, it has an inverse modulo 2²⁵⁶ such
            // that denominator * inv ≡ 1 mod 2²⁵⁶. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv ≡ 1 mod 2⁴.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also
            // works in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2⁸
            inverse *= 2 - denominator * inverse; // inverse mod 2¹⁶
            inverse *= 2 - denominator * inverse; // inverse mod 2³²
            inverse *= 2 - denominator * inverse; // inverse mod 2⁶⁴
            inverse *= 2 - denominator * inverse; // inverse mod 2¹²⁸
            inverse *= 2 - denominator * inverse; // inverse mod 2²⁵⁶

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2²⁵⁶. Since the preconditions guarantee that the outcome is
            // less than 2²⁵⁶, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }

    /// @dev Calculates x * y / denominator with full precision, following the selected rounding direction.
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (rounding == Rounding.Ceil && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }
}


/// @dev Minimal interface to call `decimals()` on the underlying token.
interface IERC20Metadata {
    function decimals() external view returns (uint8);
}
