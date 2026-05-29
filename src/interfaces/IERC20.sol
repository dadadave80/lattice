// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC20
/// @notice Interface for the ERC-20 token standard plus ERC-20 metadata extension.
interface IERC20 {
    /// @dev Emitted when `value` tokens are moved from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @dev Emitted when the allowance of a `spender` for an `owner` is set.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @dev The `sender`'s balance is insufficient for the operation.
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /// @dev `sender` is the zero address.
    error ERC20InvalidSender(address sender);

    /// @dev `receiver` is the zero address.
    error ERC20InvalidReceiver(address receiver);

    /// @dev The spender does not have enough allowance.
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    /// @dev The approver is the zero address.
    error ERC20InvalidApprover(address approver);

    /// @dev The spender is the zero address.
    error ERC20InvalidSpender(address spender);

    /// @notice Returns the total token supply.
    function totalSupply() external view returns (uint256);

    /// @notice Returns the token balance of `account`.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Transfers `value` tokens from the caller to `to`.
    function transfer(address to, uint256 value) external returns (bool);

    /// @notice Returns the remaining number of tokens that `spender` can spend on behalf of `owner`.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Sets `value` as the allowance of `spender` over the caller's tokens.
    function approve(address spender, uint256 value) external returns (bool);

    /// @notice Transfers `value` tokens from `from` to `to` using the caller's allowance.
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    /// @notice Returns the name of the token.
    function name() external view returns (string memory);

    /// @notice Returns the symbol of the token.
    function symbol() external view returns (string memory);

    /// @notice Returns the number of decimals.
    function decimals() external view returns (uint8);
}
