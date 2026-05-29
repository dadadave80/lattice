// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20BurnableLib} from "@lattice/tokens/libraries/ERC20BurnableLib.sol";
import {ERC20} from "@lattice/tokens/ERC20.sol";
import {IERC20Burnable} from "@lattice/interfaces/IERC20Burnable.sol";

/// @title ERC20Burnable
/// @notice Stateless Diamond facet adding burn operations to ERC-20.
/// @dev Inherits ERC20 and delegates burn/burnFrom to ERC20BurnableLib.
contract ERC20Burnable is ERC20, IERC20Burnable {
    /// @inheritdoc IERC20Burnable
    function burn(uint256 value) public virtual {
        ERC20BurnableLib.burn(value);
    }

    /// @inheritdoc IERC20Burnable
    function burnFrom(address account, uint256 value) public virtual {
        ERC20BurnableLib.burnFrom(account, value);
    }
}
