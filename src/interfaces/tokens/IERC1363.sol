// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC1363
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/interfaces/IERC1363.sol)
/// @notice Interface of the ERC-1363 payable token (https://eips.ethereum.org/EIPS/eip-1363): an ERC-20 extension
///         that calls the recipient after `transfer`/`transferFrom` and the spender after `approve`, in one
///         transaction. Its interfaceId is the canonical `0xb0202a11`.
/// @dev Declares only the six ERC-1363 functions, so `type(IERC1363).interfaceId` is the standard id. The ERC-20
///      surface stays under {IERC20} and ERC-165 under the diamond's `supportsInterface`. The errors come from
///      OpenZeppelin's `ERC1363` (the three `*Failed`) and `ERC1363Utils` (the two `Invalid*`).
interface IERC1363 {
    /// @dev The transfer part of a `transferAndCall` returned false.
    error ERC1363TransferFailed(address receiver, uint256 value);

    /// @dev The transferFrom part of a `transferFromAndCall` returned false.
    error ERC1363TransferFromFailed(address sender, address receiver, uint256 value);

    /// @dev The approve part of an `approveAndCall` returned false.
    error ERC1363ApproveFailed(address spender, uint256 value);

    /// @dev `receiver` has no code, or did not accept the transfer.
    error ERC1363InvalidReceiver(address receiver);

    /// @dev `spender` has no code, or did not accept the approval.
    error ERC1363InvalidSpender(address spender);

    /// @notice Moves `value` tokens from the caller to `to`, then calls {IERC1363Receiver-onTransferReceived} on `to`.
    /// @return True unless it reverts.
    function transferAndCall(address to, uint256 value) external returns (bool);

    /// @notice Variant of {transferAndCall} that forwards `data` to the receiver.
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);

    /// @notice Moves `value` tokens from `from` to `to` using the caller's allowance, then calls
    ///         {IERC1363Receiver-onTransferReceived} on `to`.
    /// @return True unless it reverts.
    function transferFromAndCall(address from, address to, uint256 value) external returns (bool);

    /// @notice Variant of {transferFromAndCall} that forwards `data` to the receiver.
    function transferFromAndCall(address from, address to, uint256 value, bytes calldata data) external returns (bool);

    /// @notice Sets `value` as `spender`'s allowance over the caller's tokens, then calls
    ///         {IERC1363Spender-onApprovalReceived} on `spender`.
    /// @return True unless it reverts.
    function approveAndCall(address spender, uint256 value) external returns (bool);

    /// @notice Variant of {approveAndCall} that forwards `data` to the spender.
    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool);
}

/// @title IERC1363Receiver
/// @notice Interface for contracts that accept ERC-1363 `transferAndCall` and `transferFromAndCall` transfers.
interface IERC1363Receiver {
    /// @notice Handles an ERC-1363 transfer. The token calls it after the balances have moved.
    /// @param operator The caller of `transferAndCall` or `transferFromAndCall`.
    /// @param from The account the tokens came from.
    /// @param value The amount transferred.
    /// @param data Additional data with no specified format.
    /// @return `IERC1363Receiver.onTransferReceived.selector` to accept the transfer.
    function onTransferReceived(address operator, address from, uint256 value, bytes calldata data)
        external
        returns (bytes4);
}

/// @title IERC1363Spender
/// @notice Interface for contracts that accept ERC-1363 `approveAndCall` approvals.
interface IERC1363Spender {
    /// @notice Handles an ERC-1363 approval. The token calls it after the allowance is set.
    /// @param owner The account that approved the tokens.
    /// @param value The amount approved.
    /// @param data Additional data with no specified format.
    /// @return `IERC1363Spender.onApprovalReceived.selector` to accept the approval.
    function onApprovalReceived(address owner, uint256 value, bytes calldata data) external returns (bytes4);
}
