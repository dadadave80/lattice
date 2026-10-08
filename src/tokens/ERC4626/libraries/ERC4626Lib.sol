// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

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
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol)
/// @notice Library implementing the ERC-4626 Tokenized Vault Standard.
/// @dev Mirrors OpenZeppelin v5 ERC4626 logic. All state lives in an ERC-7201 slot.
///      The vault IS an ERC-20 share token — callers must also initialize ERC20Lib.
///
///      NAV source: OZ prices shares through the virtual `totalAssets()`, but a library call cannot dispatch
///      virtually. Every conversion, preview, `max*` and mutator therefore reads the NAV from the diamond's own
///      `totalAssets()` selector through a self-staticcall. On a plain ERC-4626 diamond that selector is the
///      {ERC4626} facet (this library's idle-only {totalAssets}); on a VaultCore diamond it is {VaultCore},
///      which adds strategy-deployed funds. {totalAssets} here never makes that self-call, so it cannot recurse.
///
///      Liquidity: exits pay out of the vault's own balance only, so `maxWithdraw`/`maxRedeem` are capped at
///      idle assets. If the NAV read fails (e.g. a strategy's balance read reverts), the vault fails closed:
///      every `max*` returns 0, deposit/mint/withdraw/redeem revert with the matching `ERC4626ExceededMax*`
///      error, and the converters and previews revert with the NAV read's error. On a VaultCore diamond
///      `totalAssets()` itself reverts while the NAV is unreadable: the self-staticcall has no other way to
///      signal an unknown NAV. Reverting `totalAssets()`, converters and previews deviate from ERC-4626's
///      "MUST NOT revert" wording, which is preferred over pricing shares on a partial NAV.
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
    ///
    ///      IMPORTANT: `decimalsOffset_` is stored once at init time and is immutable thereafter.
    ///      Unlike OZ's `_decimalsOffset()` which is an overridable `internal view virtual` function,
    ///      Lattice's Diamond-pattern constraint requires state to live in the ERC-7201 slot — there is
    ///      no constructor and facets cannot hold mutable storage. Consumers who need a non-zero offset
    ///      must supply it via this initializer. There is no upgrade path once set.
    /// @param asset_ The underlying ERC-20 token address.
    /// @param decimalsOffset_ Virtual share decimals offset for inflation-attack mitigation (usually 0).
    function __ERC4626_init(address asset_, uint8 decimalsOffset_) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);

        ERC4626Storage storage $ = erc4626Storage();
        $._asset = asset_;
        $._decimalsOffset = decimalsOffset_;

        // Try to fetch underlying decimals; default to 18 on failure.
        // Uses a low-level staticcall with an explicit upper-bound check (per OZ v5.1.0) to avoid
        // silent truncation when a token returns a uint256 value larger than type(uint8).max.
        uint8 underlyingDecimals_ = 18;
        (bool success, bytes memory encodedDecimals) = asset_.staticcall(abi.encodeWithSignature("decimals()"));
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) {
                underlyingDecimals_ = uint8(returnedDecimals);
            }
        }
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

    /// @notice Returns the vault's idle assets: its own balance of the underlying.
    /// @dev This is the {ERC4626} facet's `totalAssets()` and the liquidity cap on exits. It is NOT the
    ///      pricing NAV on a diamond that replaces the `totalAssets()` selector (e.g. {VaultCore}); share math
    ///      reads that selector instead (see the library NatSpec). It must never call the converters.
    function totalAssets() internal view returns (uint256) {
        return IERC20(erc4626Storage()._asset).balanceOf(address(this));
    }

    /// @notice Returns shares equivalent to `assets` at the diamond's NAV (floor rounding).
    function convertToShares(uint256 assets) internal view returns (uint256) {
        return _convertToShares(assets, Rounding.Floor);
    }

    /// @notice Returns assets equivalent to `shares` at the diamond's NAV (floor rounding).
    function convertToAssets(uint256 shares) internal view returns (uint256) {
        return _convertToAssets(shares, Rounding.Floor);
    }

    /// @notice Returns the maximum depositable assets for `receiver`: unbounded, or 0 while the NAV is unreadable.
    function maxDeposit(address) internal view returns (uint256) {
        (bool ok,) = _tryNav();
        return ok ? type(uint256).max : 0;
    }

    /// @notice Returns the maximum mintable shares for `receiver`: unbounded, or 0 while the NAV is unreadable.
    function maxMint(address) internal view returns (uint256) {
        (bool ok,) = _tryNav();
        return ok ? type(uint256).max : 0;
    }

    /// @notice Returns the maximum withdrawable assets for `owner`: the NAV value of their shares, capped at
    ///         idle assets (0 while the NAV is unreadable).
    function maxWithdraw(address owner) internal view returns (uint256) {
        (bool ok, uint256 nav) = _tryNav();
        if (!ok) return 0;
        return _maxWithdraw(owner, ERC20Lib.totalSupply(), nav);
    }

    /// @notice Returns the maximum redeemable shares for `owner`: their balance, capped at the shares idle
    ///         assets can pay out (0 while the NAV is unreadable).
    function maxRedeem(address owner) internal view returns (uint256) {
        (bool ok, uint256 nav) = _tryNav();
        if (!ok) return 0;
        return _maxRedeem(owner, ERC20Lib.totalSupply(), nav);
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

    // Each mutator reads the NAV once and applies the same checks and rounding as its `max*`/`preview*` pair.

    /// @notice Deposits `assets` and mints shares to `receiver`.
    function deposit(uint256 assets, address receiver) internal returns (uint256 shares) {
        (bool ok, uint256 nav) = _tryNav();
        if (!ok) revert IERC4626.ERC4626ExceededMaxDeposit(receiver, assets, 0);
        shares = _convertToSharesFromTotals(assets, ERC20Lib.totalSupply(), nav, _decimalsOffset(), Rounding.Floor);
        _deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Mints exactly `shares` to `receiver`, pulling the required assets.
    function mint(uint256 shares, address receiver) internal returns (uint256 assets) {
        (bool ok, uint256 nav) = _tryNav();
        if (!ok) revert IERC4626.ERC4626ExceededMaxMint(receiver, shares, 0);
        assets = _convertToAssetsFromTotals(shares, ERC20Lib.totalSupply(), nav, _decimalsOffset(), Rounding.Ceil);
        _deposit(msg.sender, receiver, assets, shares);
    }

    /// @notice Withdraws `assets` from the vault, burning the required shares from `owner`.
    function withdraw(uint256 assets, address receiver, address owner) internal returns (uint256 shares) {
        (bool ok, uint256 nav) = _tryNav();
        uint256 supply = ERC20Lib.totalSupply();
        uint256 maxAssets = ok ? _maxWithdraw(owner, supply, nav) : 0;
        if (!ok || assets > maxAssets) {
            revert IERC4626.ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }
        shares = _convertToSharesFromTotals(assets, supply, nav, _decimalsOffset(), Rounding.Ceil);
        _withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /// @notice Redeems `shares` from `owner`, transferring assets to `receiver`.
    function redeem(uint256 shares, address receiver, address owner) internal returns (uint256 assets) {
        (bool ok, uint256 nav) = _tryNav();
        uint256 supply = ERC20Lib.totalSupply();
        uint256 maxShares = ok ? _maxRedeem(owner, supply, nav) : 0;
        if (!ok || shares > maxShares) {
            revert IERC4626.ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }
        assets = _convertToAssetsFromTotals(shares, supply, nav, _decimalsOffset(), Rounding.Floor);
        _withdraw(msg.sender, receiver, owner, assets, shares);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Converts `assets` to shares at the diamond's NAV using the given rounding direction.
    function _convertToShares(uint256 assets, Rounding rounding) internal view returns (uint256) {
        return _convertToSharesFromTotals(assets, ERC20Lib.totalSupply(), _nav(), _decimalsOffset(), rounding);
    }

    /// @dev Converts `shares` to assets at the diamond's NAV using the given rounding direction.
    function _convertToAssets(uint256 shares, Rounding rounding) internal view returns (uint256) {
        return _convertToAssetsFromTotals(shares, ERC20Lib.totalSupply(), _nav(), _decimalsOffset(), rounding);
    }

    /// @dev Converts `assets` to shares from explicit totals.
    ///      Formula: assets * (totalSupply + 10**offset) / (totalAssets + 1)
    function _convertToSharesFromTotals(
        uint256 assets,
        uint256 totalSupply_,
        uint256 totalAssets_,
        uint8 decimalsOffset_,
        Rounding rounding
    ) internal pure returns (uint256) {
        return mulDiv(assets, totalSupply_ + 10 ** uint256(decimalsOffset_), totalAssets_ + 1, rounding);
    }

    /// @dev Converts `shares` to assets from explicit totals.
    ///      Formula: shares * (totalAssets + 1) / (totalSupply + 10**offset)
    function _convertToAssetsFromTotals(
        uint256 shares,
        uint256 totalSupply_,
        uint256 totalAssets_,
        uint8 decimalsOffset_,
        Rounding rounding
    ) internal pure returns (uint256) {
        return mulDiv(shares, totalAssets_ + 1, totalSupply_ + 10 ** uint256(decimalsOffset_), rounding);
    }

    /// @dev `maxWithdraw` at a known NAV: the floor value of `owner`'s shares, capped at idle assets.
    function _maxWithdraw(address owner, uint256 totalSupply_, uint256 nav) private view returns (uint256) {
        uint256 owed =
            _convertToAssetsFromTotals(ERC20Lib.balanceOf(owner), totalSupply_, nav, _decimalsOffset(), Rounding.Floor);
        uint256 idle = totalAssets();
        return owed < idle ? owed : idle;
    }

    /// @dev `maxRedeem` at a known NAV: `owner`'s balance, capped at the floor shares idle assets buy back.
    ///      Floor then floor keeps `previewRedeem(maxRedeem)` within idle.
    function _maxRedeem(address owner, uint256 totalSupply_, uint256 nav) private view returns (uint256) {
        uint256 balance = ERC20Lib.balanceOf(owner);
        uint256 idleShares =
            _convertToSharesFromTotals(totalAssets(), totalSupply_, nav, _decimalsOffset(), Rounding.Floor);
        return balance < idleShares ? balance : idleShares;
    }

    function _decimalsOffset() private view returns (uint8) {
        return erc4626Storage()._decimalsOffset;
    }

    /// @dev Reads the NAV from the diamond's own `totalAssets()` selector, bubbling its revert on failure.
    function _nav() private view returns (uint256) {
        (bool ok, bytes memory data) = _navStaticcall();
        if (!ok || data.length < 32) {
            assembly ("memory-safe") {
                revert(add(data, 0x20), mload(data))
            }
        }
        return abi.decode(data, (uint256));
    }

    /// @dev Reads the NAV from the diamond's own `totalAssets()` selector; `ok` is false if the read failed.
    function _tryNav() private view returns (bool ok, uint256 nav) {
        bytes memory data;
        (ok, data) = _navStaticcall();
        if (!ok || data.length < 32) return (false, 0);
        nav = abi.decode(data, (uint256));
    }

    /// @dev Self-staticcall to `totalAssets()`, which dispatches to whichever facet owns that selector.
    function _navStaticcall() private view returns (bool ok, bytes memory data) {
        (ok, data) = address(this).staticcall(abi.encodeWithSelector(IERC4626.totalAssets.selector));
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
        // Success requires the call to succeed AND either (a) return a truthy bool, or (b) return
        // no data but be a contract. A no-code address returns ok=true with empty data, which must
        // NOT be treated as a successful transfer (matches OpenZeppelin SafeERC20).
        if (!ok || (ret.length == 0 ? token.code.length == 0 : !abi.decode(ret, (bool)))) {
            revert IERC4626.SafeERC20FailedOperation(token);
        }
    }

    /// @dev Calls `token.transferFrom(from, to, amount)` and reverts with SafeERC20FailedOperation if it
    ///      fails or returns false. Handles tokens that do not return a bool (e.g. USDT).
    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        // Success requires the call to succeed AND either (a) return a truthy bool, or (b) return
        // no data but be a contract. A no-code address returns ok=true with empty data, which must
        // NOT be treated as a successful transfer (matches OpenZeppelin SafeERC20).
        if (!ok || (ret.length == 0 ? token.code.length == 0 : !abi.decode(ret, (bool)))) {
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
            // slither-disable-next-line incorrect-exp XOR is intended: the 4-bit Newton-Raphson seed
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

