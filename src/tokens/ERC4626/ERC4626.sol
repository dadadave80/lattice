// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";

/// @title ERC4626
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol)
/// @notice Stateless Diamond facet for the ERC-4626 Tokenized Vault Standard.
/// @dev All logic lives in ERC4626Lib. This contract is a pure delegator.
///      Inherits ERC20 (the vault's share token) and implements IERC4626.
///
///      Callers must initialize the following modules in their initializer:
///        - ERC20Lib.__ERC20_init(name, symbol)
///        - ERC4626Lib.__ERC4626_init(asset, decimalsOffset)
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract ERC4626 is ERC20, IERC4626 {
    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-20 OVERRIDES
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the vault's decimals: underlying asset decimals + offset.
    /// @dev Overrides ERC20's default of 18.
    function decimals() public view virtual override(ERC20, IERC20) returns (uint8) {
        return ERC4626Lib.decimals();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          IERC4626 — VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IERC4626
    function asset() public view virtual returns (address) {
        return ERC4626Lib.asset();
    }

    /// @inheritdoc IERC4626
    function totalAssets() public view virtual returns (uint256) {
        return ERC4626Lib.totalAssets();
    }

    /// @inheritdoc IERC4626
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return ERC4626Lib.convertToShares(assets);
    }

    /// @inheritdoc IERC4626
    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return ERC4626Lib.convertToAssets(shares);
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address receiver) public view virtual returns (uint256) {
        return ERC4626Lib.maxDeposit(receiver);
    }

    /// @inheritdoc IERC4626
    function maxMint(address receiver) public view virtual returns (uint256) {
        return ERC4626Lib.maxMint(receiver);
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return ERC4626Lib.maxWithdraw(owner);
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address owner) public view virtual returns (uint256) {
        return ERC4626Lib.maxRedeem(owner);
    }

    /// @inheritdoc IERC4626
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return ERC4626Lib.previewDeposit(assets);
    }

    /// @inheritdoc IERC4626
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        return ERC4626Lib.previewMint(shares);
    }

    /// @inheritdoc IERC4626
    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return ERC4626Lib.previewWithdraw(assets);
    }

    /// @inheritdoc IERC4626
    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return ERC4626Lib.previewRedeem(shares);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     IERC4626 — STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IERC4626
    function deposit(uint256 assets, address receiver) public virtual returns (uint256) {
        return ERC4626Lib.deposit(assets, receiver);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 shares, address receiver) public virtual returns (uint256) {
        return ERC4626Lib.mint(shares, receiver);
    }

    /// @inheritdoc IERC4626
    function withdraw(uint256 assets, address receiver, address owner) public virtual returns (uint256) {
        return ERC4626Lib.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc IERC4626
    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256) {
        return ERC4626Lib.redeem(shares, receiver, owner);
    }
}
