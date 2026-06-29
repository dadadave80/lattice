// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20Wrapper} from "@lattice/interfaces/tokens/IERC20Wrapper.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20WrapperLib} from "@lattice/tokens/ERC20/libraries/ERC20WrapperLib.sol";

/// @title ERC20Wrapper
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Wrapper.sol)
/// @notice Stateless Diamond facet — wraps an underlying ERC-20 1:1. Pure delegator to {ERC20WrapperLib}.
/// @dev `recover()` is intentionally NOT exposed here: exposing it requires access control, so a deriving facet
///      adds it. `decimals()` overrides the base 18 to mirror the underlying.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC20Wrapper is ERC20, IERC20Wrapper {
    /// @inheritdoc ERC20
    function decimals() public view virtual override returns (uint8) {
        return ERC20WrapperLib.decimals();
    }

    /// @inheritdoc IERC20Wrapper
    function underlying() public view virtual returns (address) {
        return ERC20WrapperLib.underlying();
    }

    /// @inheritdoc IERC20Wrapper
    function depositFor(address account, uint256 value) public virtual returns (bool) {
        return ERC20WrapperLib.depositFor(account, value);
    }

    /// @inheritdoc IERC20Wrapper
    function withdrawTo(address account, uint256 value) public virtual returns (bool) {
        return ERC20WrapperLib.withdrawTo(account, value);
    }
}
