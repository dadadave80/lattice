// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC20Wrapper
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Wrapper.sol)
/// @notice Interface for the ERC-20 wrapper extension: deposit an underlying ERC-20 to mint matching wrapped
///         tokens 1:1, and burn wrapped tokens to withdraw the underlying.
interface IERC20Wrapper {
    /// @notice The underlying token couldn't be wrapped (e.g. it is the wrapper itself).
    error ERC20InvalidUnderlying(address token);

    /// @notice A safe ERC-20 transfer of the underlying token failed.
    error SafeERC20FailedOperation(address token);

    /// @notice The address of the underlying ERC-20 token being wrapped.
    function underlying() external view returns (address);

    /// @notice Deposit `value` underlying tokens from the caller and mint the same number of wrapped tokens to
    ///         `account`.
    function depositFor(address account, uint256 value) external returns (bool);

    /// @notice Burn `value` wrapped tokens from the caller and send the same number of underlying tokens to
    ///         `account`.
    function withdrawTo(address account, uint256 value) external returns (bool);
}
