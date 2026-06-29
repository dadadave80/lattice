// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Wrapper} from "@lattice/interfaces/tokens/IERC20Wrapper.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC20Wrapper")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC20WRAPPER_STORAGE_SLOT = 0x9af643d743ece491f2a9cf5444d757c9d02a4957e91a8cb344a1642a3cb94400;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC20WRAPPER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x60237459 is `type(IERC20Wrapper).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x60237459), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC20WRAPPER_SLOT = 0xbf9f024bc4077d1561e72f01e7eabc003cc7b8d081de85f0fd1662da93832e2b;

/// @notice Storage struct for the ERC-20 wrapper.
/// @custom:storage-location erc7201:lattice.storage.ERC20Wrapper
struct ERC20WrapperStorage {
    address _underlying;
    uint8 _underlyingDecimals;
}

/// @title ERC20WrapperLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Wrapper.sol)
/// @notice Library implementing 1:1 wrapping of an underlying ERC-20. All logic lives here; the facet delegates.
/// @dev WARNING: an underlying that changes balances without an explicit transfer (rebasing / fee-on-transfer)
///      can desynchronise this wrapper's supply and its underlying balance; use {recover} to mint the surplus.
library ERC20WrapperLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc20WrapperStorage() internal pure returns (ERC20WrapperStorage storage $) {
        assembly {
            $.slot := ERC20WRAPPER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the wrapper with its underlying token.
    /// @dev Must be called inside a pre/postInitializer block. Reverts if `underlying_` is the wrapper itself.
    ///      Caches the underlying's `decimals()` (default 18 on failure, per OZ) so {decimals} matches it.
    function __ERC20Wrapper_init(address underlying_) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        if (underlying_ == address(this)) revert IERC20Wrapper.ERC20InvalidUnderlying(address(this));

        ERC20WrapperStorage storage $ = erc20WrapperStorage();
        $._underlying = underlying_;

        uint8 underlyingDecimals_ = 18;
        (bool success, bytes memory encodedDecimals) = underlying_.staticcall(abi.encodeWithSignature("decimals()"));
        if (success && encodedDecimals.length >= 32) {
            uint256 returnedDecimals = abi.decode(encodedDecimals, (uint256));
            if (returnedDecimals <= type(uint8).max) underlyingDecimals_ = uint8(returnedDecimals);
        }
        $._underlyingDecimals = underlyingDecimals_;

        registerInterface();
    }

    /// @notice Registers support for the IERC20Wrapper interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC20WRAPPER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The underlying ERC-20 token being wrapped.
    function underlying() internal view returns (address) {
        return erc20WrapperStorage()._underlying;
    }

    /// @notice The wrapper's decimals — mirrors the underlying token's decimals.
    function decimals() internal view returns (uint8) {
        return erc20WrapperStorage()._underlyingDecimals;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            WRAP / UNWRAP
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Pulls `value` underlying from the caller and mints `value` wrapped tokens to `account`.
    function depositFor(address account, uint256 value) internal returns (bool) {
        address sender = msg.sender;
        if (sender == address(this)) revert IERC20.ERC20InvalidSender(address(this));
        if (account == address(this)) revert IERC20.ERC20InvalidReceiver(account);
        _safeTransferFrom(underlying(), sender, address(this), value);
        ERC20Lib._mint(account, value);
        return true;
    }

    /// @notice Burns `value` wrapped tokens from the caller and sends `value` underlying to `account`.
    function withdrawTo(address account, uint256 value) internal returns (bool) {
        if (account == address(this)) revert IERC20.ERC20InvalidReceiver(account);
        ERC20Lib._burn(msg.sender, value);
        _safeTransfer(underlying(), account, value);
        return true;
    }

    /// @notice Mints wrapped tokens to `account` covering any underlying surplus (mis-sent / rebased in).
    /// @dev Internal — a facet exposing this MUST add access control. Not on the base {ERC20Wrapper} facet.
    function recover(address account) internal returns (uint256) {
        uint256 value = IERC20(underlying()).balanceOf(address(this)) - ERC20Lib.totalSupply();
        ERC20Lib._mint(account, value);
        return value;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          SAFE TRANSFER HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev `token.transfer(to, amount)`, reverting with {SafeERC20FailedOperation}. Handles no-bool tokens (USDT).
    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        if (!ok || (ret.length == 0 ? token.code.length == 0 : !abi.decode(ret, (bool)))) {
            revert IERC20Wrapper.SafeERC20FailedOperation(token);
        }
    }

    /// @dev `token.transferFrom(from, to, amount)`, reverting with {SafeERC20FailedOperation}. Handles USDT-likes.
    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount));
        if (!ok || (ret.length == 0 ? token.code.length == 0 : !abi.decode(ret, (bool)))) {
            revert IERC20Wrapper.SafeERC20FailedOperation(token);
        }
    }
}
