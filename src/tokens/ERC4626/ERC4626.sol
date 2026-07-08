// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";

/// @title ERC4626
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol)
/// @notice Stateless Diamond facet for the ERC-4626 Tokenized Vault Standard.
/// @dev All logic lives in ERC4626Lib. This contract is a pure delegator. It owns ONLY the vault surface
///      (`asset`/`totalAssets`/convert*/preview*/max*/deposit/mint/withdraw/redeem) plus the `decimals()`
///      override (the share offset), which REPLACES the base {ERC20} variant. It does NOT inherit the {ERC20}
///      facet — doing so would re-export the ERC-20 share selectors and collide with the standalone {ERC20}
///      facet in a Diamond (and `is IERC4626` would drag in the whole IERC20 surface, forcing a re-export).
///      The ERC-20 share surface comes from a separately-cut {ERC20} facet; {DeployERC4626} composes both over
///      one shared storage layout. The assembled diamond IS-A ERC-4626 (IERC4626), enforced by the recipe, not
///      by facet-level inheritance.
///
///      Callers must initialize the following modules in their initializer:
///        - ERC20Lib.__ERC20_init(name, symbol)
///        - ERC4626Lib.__ERC4626_init(asset, decimalsOffset)
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract ERC4626 {
    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-20 OVERRIDE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the vault's decimals: underlying asset decimals + offset.
    /// @dev Replaces the base {ERC20} default of 18.
    function decimals() public view virtual returns (uint8) {
        return ERC4626Lib.decimals();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          IERC4626 — VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the address of the underlying ERC-20 asset the vault holds.
    function asset() public view virtual returns (address) {
        return ERC4626Lib.asset();
    }

    /// @notice Returns the total amount of the underlying asset managed by the vault.
    function totalAssets() public view virtual returns (uint256) {
        return ERC4626Lib.totalAssets();
    }

    /// @notice Converts `assets` of the underlying to the equivalent amount of vault shares.
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        return ERC4626Lib.convertToShares(assets);
    }

    /// @notice Converts `shares` of the vault to the equivalent amount of underlying assets.
    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        return ERC4626Lib.convertToAssets(shares);
    }

    /// @notice Returns the maximum assets that can be deposited for `receiver`.
    function maxDeposit(address receiver) public view virtual returns (uint256) {
        return ERC4626Lib.maxDeposit(receiver);
    }

    /// @notice Returns the maximum shares that can be minted for `receiver`.
    function maxMint(address receiver) public view virtual returns (uint256) {
        return ERC4626Lib.maxMint(receiver);
    }

    /// @notice Returns the maximum assets that can be withdrawn by `owner`.
    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return ERC4626Lib.maxWithdraw(owner);
    }

    /// @notice Returns the maximum shares that can be redeemed by `owner`.
    function maxRedeem(address owner) public view virtual returns (uint256) {
        return ERC4626Lib.maxRedeem(owner);
    }

    /// @notice Simulates the shares minted for a deposit of `assets` at the current block.
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return ERC4626Lib.previewDeposit(assets);
    }

    /// @notice Simulates the assets required to mint `shares` at the current block.
    function previewMint(uint256 shares) public view virtual returns (uint256) {
        return ERC4626Lib.previewMint(shares);
    }

    /// @notice Simulates the shares burned for a withdrawal of `assets` at the current block.
    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        return ERC4626Lib.previewWithdraw(assets);
    }

    /// @notice Simulates the assets returned for redeeming `shares` at the current block.
    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return ERC4626Lib.previewRedeem(shares);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     IERC4626 — STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Deposits `assets` of the underlying and mints vault shares to `receiver`.
    function deposit(uint256 assets, address receiver) public virtual returns (uint256) {
        return ERC4626Lib.deposit(assets, receiver);
    }

    /// @notice Mints exactly `shares` to `receiver`, pulling the required underlying assets.
    function mint(uint256 shares, address receiver) public virtual returns (uint256) {
        return ERC4626Lib.mint(shares, receiver);
    }

    /// @notice Withdraws exactly `assets` to `receiver`, burning `owner`'s shares.
    function withdraw(uint256 assets, address receiver, address owner) public virtual returns (uint256) {
        return ERC4626Lib.withdraw(assets, receiver, owner);
    }

    /// @notice Redeems exactly `shares` from `owner`, sending the underlying assets to `receiver`.
    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256) {
        return ERC4626Lib.redeem(shares, receiver, owner);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC4626 methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `asset()` 0x38d52e0f
    ///      `convertToAssets(uint256)` 0x07a2d13a
    ///      `convertToShares(uint256)` 0xc6e6f592
    ///      `decimals()` 0x313ce567
    ///      `deposit(uint256,address)` 0x6e553f65
    ///      `maxDeposit(address)` 0x402d267d
    ///      `maxMint(address)` 0xc63d75b6
    ///      `maxRedeem(address)` 0xd905777e
    ///      `maxWithdraw(address)` 0xce96cb77
    ///      `mint(uint256,address)` 0x94bf804d
    ///      `previewDeposit(uint256)` 0xef8b30f7
    ///      `previewMint(uint256)` 0xb3d7f6b9
    ///      `previewRedeem(uint256)` 0x4cdad506
    ///      `previewWithdraw(uint256)` 0x0a28a477
    ///      `redeem(uint256,address,address)` 0xba087652
    ///      `totalAssets()` 0x01e1d114
    ///      `withdraw(uint256,address,address)` 0xb460af94
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
            hex"38d52e0f07a2d13ac6e6f592313ce5676e553f65402d267dc63d75b6d905777ece96cb7794bf804def8b30f7b3d7f6b94cdad5060a28a477ba08765201e1d114b460af94";
    }
}
