// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC1155
/// @notice Interface for the ERC-1155 Multi-Token Standard, including metadata URI extension.
interface IERC1155 {
    /// @dev Emitted when `value` tokens of token type `id` are transferred from `from` to `to` by `operator`.
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    /// @dev Equivalent to multiple {TransferSingle} events, where `operator`, `from`, and `to` are the same for all.
    event TransferBatch(
        address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values
    );

    /// @dev Emitted when `account` grants or revokes permission to `operator` to transfer their tokens.
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    /// @dev Emitted when the URI for token type `id` changes to `value`, if it is a non-programmatic URI.
    event URI(string value, uint256 indexed id);

    /// @dev Sender does not have sufficient balance for the operation.
    error ERC1155InsufficientBalance(address sender, uint256 balance, uint256 needed, uint256 tokenId);

    /// @dev `sender` is the zero address.
    error ERC1155InvalidSender(address sender);

    /// @dev `receiver` is the zero address or does not implement IERC1155Receiver correctly.
    error ERC1155InvalidReceiver(address receiver);

    /// @dev `operator` is not approved and the caller is not the owner.
    error ERC1155MissingApprovalForAll(address operator, address owner);

    /// @dev `approver` is the zero address.
    error ERC1155InvalidApprover(address approver);

    /// @dev `operator` is the zero address.
    error ERC1155InvalidOperator(address operator);

    /// @dev Array lengths of `ids` and `values` do not match.
    error ERC1155InvalidArrayLength(uint256 idsLength, uint256 valuesLength);

    /// @notice Returns the amount of tokens of token type `id` owned by `account`.
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /// @notice Batched version of {balanceOf}.
    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);

    /// @notice Grants or revokes permission to `operator` to transfer the caller's tokens.
    function setApprovalForAll(address operator, bool approved) external;

    /// @notice Returns true if `operator` is approved to transfer `account`'s tokens.
    function isApprovedForAll(address account, address operator) external view returns (bool);

    /// @notice Transfers `value` amount of an `id` from `from` to `to`.
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external;

    /// @notice Batched version of {safeTransferFrom}.
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external;

    /// @notice Returns the URI for token type `id`.
    function uri(uint256 id) external view returns (string memory);
}

/// @title IERC1155Receiver
/// @notice Interface for contracts that want to receive ERC-1155 tokens.
interface IERC1155Receiver {
    /// @notice Handle the receipt of a single ERC-1155 token type.
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        returns (bytes4);

    /// @notice Handle the receipt of multiple ERC-1155 token types.
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);
}
