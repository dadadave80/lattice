// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

/// @title ERC20
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol)
/// @notice Stateless Diamond facet for the ERC-20 token standard.
/// @dev All logic lives in ERC20Lib. This contract is a pure delegator.
///      Subclasses (Burnable, Capped, Permit) override `virtual` methods.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract ERC20 is IERC20 {
    /// @inheritdoc IERC20
    function totalSupply() public view virtual returns (uint256) {
        return ERC20Lib.totalSupply();
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view virtual returns (uint256) {
        return ERC20Lib.balanceOf(account);
    }

    /// @inheritdoc IERC20
    function transfer(address to, uint256 value) public virtual returns (bool) {
        return ERC20Lib.transfer(to, value);
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return ERC20Lib.allowance(owner, spender);
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 value) public virtual returns (bool) {
        return ERC20Lib.approve(spender, value);
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        return ERC20Lib.transferFrom(from, to, value);
    }

    /// @inheritdoc IERC20
    function name() public view virtual returns (string memory) {
        return ERC20Lib.name();
    }

    /// @inheritdoc IERC20
    function symbol() public view virtual returns (string memory) {
        return ERC20Lib.symbol();
    }

    /// @inheritdoc IERC20
    function decimals() public view virtual returns (uint8) {
        return ERC20Lib.decimals();
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC20 methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `allowance(address,address)` 0xdd62ed3e
    ///      `approve(address,uint256)` 0x095ea7b3
    ///      `balanceOf(address)` 0x70a08231
    ///      `decimals()` 0x313ce567
    ///      `name()` 0x06fdde03
    ///      `symbol()` 0x95d89b41
    ///      `totalSupply()` 0x18160ddd
    ///      `transfer(address,uint256)` 0xa9059cbb
    ///      `transferFrom(address,address,uint256)` 0x23b872dd
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"dd62ed3e095ea7b370a08231313ce56706fdde0395d89b4118160ddda9059cbb23b872dd";
    }
}
