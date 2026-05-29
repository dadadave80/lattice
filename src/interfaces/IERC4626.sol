// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IERC20} from "@lattice/interfaces/IERC20.sol";

/// @title IERC4626
/// @notice Interface for the ERC-4626 Tokenized Vault Standard.
/// @dev Inherits IERC20 — the vault itself is an ERC-20 share token.
///      See https://eips.ethereum.org/EIPS/eip-4626
interface IERC4626 is IERC20 {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Emitted when `assets` are deposited into the vault by `sender`, minting `shares` to `owner`.
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    /// @dev Emitted when `shares` are redeemed from the vault by `sender` on behalf of `owner`,
    ///      transferring `assets` to `receiver`.
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev The deposit would exceed the maximum allowed for `receiver`.
    error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);

    /// @dev The mint would exceed the maximum allowed for `receiver`.
    error ERC4626ExceededMaxMint(address receiver, uint256 shares, uint256 max);

    /// @dev The withdrawal would exceed the maximum allowed for `owner`.
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);

    /// @dev The redemption would exceed the maximum allowed for `owner`.
    error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max);

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the address of the underlying asset token.
    function asset() external view returns (address);

    /// @notice Returns the total amount of underlying assets held by the vault.
    function totalAssets() external view returns (uint256);

    /// @notice Returns the number of vault shares equivalent to `assets` underlying tokens (floor rounding).
    function convertToShares(uint256 assets) external view returns (uint256);

    /// @notice Returns the number of underlying tokens equivalent to `shares` vault shares (floor rounding).
    function convertToAssets(uint256 shares) external view returns (uint256);

    /// @notice Returns the maximum amount of underlying assets `receiver` can deposit.
    function maxDeposit(address receiver) external view returns (uint256);

    /// @notice Returns the maximum number of shares `receiver` can receive via `mint`.
    function maxMint(address receiver) external view returns (uint256);

    /// @notice Returns the maximum amount of underlying assets `owner` can withdraw.
    function maxWithdraw(address owner) external view returns (uint256);

    /// @notice Returns the maximum number of shares `owner` can redeem.
    function maxRedeem(address owner) external view returns (uint256);

    /// @notice Simulates the number of shares minted for a `deposit` of `assets`.
    function previewDeposit(uint256 assets) external view returns (uint256);

    /// @notice Simulates the number of assets required to mint exactly `shares`.
    function previewMint(uint256 shares) external view returns (uint256);

    /// @notice Simulates the number of shares burned for a `withdraw` of `assets`.
    function previewWithdraw(uint256 assets) external view returns (uint256);

    /// @notice Simulates the number of assets returned for redeeming `shares`.
    function previewRedeem(uint256 shares) external view returns (uint256);

    //*//////////////////////////////////////////////////////////////////////////
    //                          STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Deposits `assets` underlying tokens and mints shares to `receiver`.
    /// @return shares The number of shares minted.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Mints exactly `shares` to `receiver` by pulling the required underlying assets.
    /// @return assets The number of assets transferred.
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /// @notice Burns shares from `owner` and sends `assets` underlying tokens to `receiver`.
    /// @return shares The number of shares burned.
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /// @notice Burns exactly `shares` from `owner` and sends underlying tokens to `receiver`.
    /// @return assets The number of assets transferred.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}
