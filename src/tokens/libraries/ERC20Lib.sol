// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC20} from "@lattice/interfaces/IERC20.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC20_STORAGE_SLOT = 0x948387732d07f6e6ec1c3bf1559c10e90e518c5a59f5d2be5a80edb6f2494300;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC20_ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x942e8b22 is `type(IERC20).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x942e8b22), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC20_SLOT = 0xc99f0f757c400475fa5e27e7e237b05409e3b11dbfd9a8930fb35692da3f3a3d;

/// @notice Storage struct for ERC-20 module.
/// @custom:storage-location erc7201:lattice.storage.ERC20
struct ERC20Storage {
    mapping(address account => uint256) _balances;
    mapping(address account => mapping(address spender => uint256)) _allowances;
    uint256 _totalSupply;
    string _name;
    string _symbol;
}

/// @title ERC20Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing the ERC-20 token standard.
/// @dev Mirrors OpenZeppelin v5 ERC20 logic. All state lives in an ERC-7201 slot.
library ERC20Lib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc20Storage() internal pure returns (ERC20Storage storage $) {
        assembly {
            $.slot := ERC20_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ERC-20 module with name and symbol.
    /// @dev Must be called inside a pre/postInitializer block.
    function __ERC20_init(string memory name_, string memory symbol_) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);

        ERC20Storage storage $ = erc20Storage();
        $._name = name_;
        $._symbol = symbol_;

        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC20 interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC20_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the total token supply.
    function totalSupply() internal view returns (uint256) {
        return erc20Storage()._totalSupply;
    }

    /// @notice Returns the token balance of `account`.
    function balanceOf(address account) internal view returns (uint256) {
        return erc20Storage()._balances[account];
    }

    /// @notice Returns the remaining allowance of `spender` over `owner`'s tokens.
    function allowance(address owner, address spender) internal view returns (uint256) {
        return erc20Storage()._allowances[owner][spender];
    }

    /// @notice Returns the token name.
    function name() internal view returns (string memory) {
        return erc20Storage()._name;
    }

    /// @notice Returns the token symbol.
    function symbol() internal view returns (string memory) {
        return erc20Storage()._symbol;
    }

    /// @notice Returns the number of decimals — always 18 unless overridden by the facet.
    function decimals() internal view returns (uint8) {
        return 18;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           TRANSFER OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Moves `value` tokens from the caller to `to`.
    function transfer(address to, uint256 value) internal returns (bool) {
        address owner = ContextLib.msgSender();
        _transfer(owner, to, value);
        return true;
    }

    /// @notice Moves `value` tokens from `from` to `to` using the caller's allowance.
    function transferFrom(address from, address to, uint256 value) internal returns (bool) {
        address spender = ContextLib.msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           APPROVAL OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets `value` as the allowance of `spender` over the caller's tokens.
    function approve(address spender, uint256 value) internal returns (bool) {
        address owner = ContextLib.msgSender();
        _approve(owner, spender, value);
        return true;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Entry-point transfer helper; reverts on zero sender or receiver.
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) revert IERC20.ERC20InvalidSender(address(0));
        if (to == address(0)) revert IERC20.ERC20InvalidReceiver(address(0));
        _update(from, to, value);
    }

    /// @notice Actual state-change for all token movements; emits Transfer.
    /// @dev This is the core function that submodules (Capped) hook into.
    function _update(address from, address to, uint256 value) internal {
        ERC20Storage storage $ = erc20Storage();

        if (from == address(0)) {
            // Mint
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            $._totalSupply += value;
        } else {
            uint256 fromBalance = $._balances[from];
            if (fromBalance < value) {
                revert IERC20.ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                $._balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            // Burn
            unchecked {
                $._totalSupply -= value;
            }
        } else {
            unchecked {
                $._balances[to] += value;
            }
        }

        emit IERC20.Transfer(from, to, value);
    }

    /// @notice Mints `value` tokens to `to`.
    function _mint(address to, uint256 value) internal {
        if (to == address(0)) revert IERC20.ERC20InvalidReceiver(address(0));
        _update(address(0), to, value);
    }

    /// @notice Burns `value` tokens from `from`.
    function _burn(address from, uint256 value) internal {
        if (from == address(0)) revert IERC20.ERC20InvalidSender(address(0));
        _update(from, address(0), value);
    }

    /// @notice 3-arg entry-point for approve operations. Always emits the Approval event.
    /// @dev This is the public hook-point for override chains (Permit, Votes extensions).
    ///      Mirrors OZ's _approve(address,address,uint256) which delegates to the 4-arg variant.
    ///      Extensions that need to intercept approval at the entry-point should shadow this.
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    /// @notice Sets the allowance and optionally emits Approval.
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal {
        if (owner == address(0)) revert IERC20.ERC20InvalidApprover(address(0));
        if (spender == address(0)) revert IERC20.ERC20InvalidSpender(address(0));
        erc20Storage()._allowances[owner][spender] = value;
        if (emitEvent) {
            emit IERC20.Approval(owner, spender, value);
        }
    }

    /// @notice Decreases the allowance of `spender` over `owner`'s tokens by `value`.
    /// @dev Skips decrement when allowance is type(uint256).max (infinite allowance).
    function _spendAllowance(address owner, address spender, uint256 value) internal {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert IERC20.ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}
