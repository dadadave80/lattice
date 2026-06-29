// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20Capped} from "@lattice/interfaces/tokens/IERC20Capped.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20CappedLib} from "@lattice/tokens/ERC20/libraries/ERC20CappedLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

/// @title ERC20Capped
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Capped.sol)
/// @notice Stateless Diamond facet for ERC-20 tokens with a capped total supply.
/// @dev Inherits ERC20. Exposes a `mint` function (access-controlled externally)
///      that enforces the cap before delegating to ERC20Lib._mint.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract ERC20Capped is ERC20, IERC20Capped {
    /// @inheritdoc IERC20Capped
    function cap() public view virtual returns (uint256) {
        return ERC20CappedLib.cap();
    }

    /// @notice Mints `value` tokens to `to`, reverting if the cap would be exceeded.
    /// @dev Callers are responsible for access control.
    function _mint(address to, uint256 value) internal virtual {
        ERC20CappedLib._checkCap(ERC20Lib.totalSupply() + value);
        ERC20Lib._mint(to, value);
    }
}
