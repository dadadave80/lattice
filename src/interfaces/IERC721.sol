// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC721
/// @notice Interface for the ERC-721 Non-Fungible Token standard, including metadata extension.
interface IERC721 {
    /// @dev Emitted when `tokenId` is transferred from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /// @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /// @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /// @dev `owner` is the zero address — invalid owner.
    error ERC721InvalidOwner(address owner);

    /// @dev `tokenId` does not exist.
    error ERC721NonexistentToken(uint256 tokenId);

    /// @dev `sender` is not the owner of `tokenId`. The owner is `owner`.
    error ERC721IncorrectOwner(address sender, uint256 tokenId, address owner);

    /// @dev `sender` is the zero address — invalid sender.
    error ERC721InvalidSender(address sender);

    /// @dev `receiver` is the zero address or does not implement IERC721Receiver correctly.
    error ERC721InvalidReceiver(address receiver);

    /// @dev `operator` is not approved and does not have sufficient authorization for `tokenId`.
    error ERC721InsufficientApproval(address operator, uint256 tokenId);

    /// @dev `approver` is the zero address or is not the owner of the token.
    error ERC721InvalidApprover(address approver);

    /// @dev `operator` is the zero address.
    error ERC721InvalidOperator(address operator);

    /// @notice Returns the number of tokens owned by `owner`.
    function balanceOf(address owner) external view returns (uint256 balance);

    /// @notice Returns the owner of the `tokenId` token.
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /// @notice Safely transfers `tokenId` from `from` to `to` with additional `data`.
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

    /// @notice Safely transfers `tokenId` from `from` to `to`.
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /// @notice Transfers `tokenId` from `from` to `to` without safety checks.
    function transferFrom(address from, address to, uint256 tokenId) external;

    /// @notice Approves `to` to transfer `tokenId` on behalf of the caller.
    function approve(address to, uint256 tokenId) external;

    /// @notice Enables or disables approval for `operator` to manage all of the caller's assets.
    function setApprovalForAll(address operator, bool approved) external;

    /// @notice Returns the address approved for `tokenId`.
    function getApproved(uint256 tokenId) external view returns (address operator);

    /// @notice Returns true if `operator` is approved to manage all of `owner`'s assets.
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /// @notice Returns the token name.
    function name() external view returns (string memory);

    /// @notice Returns the token symbol.
    function symbol() external view returns (string memory);

    /// @notice Returns the Uniform Resource Identifier (URI) for `tokenId` token.
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

/// @title IERC721Receiver
/// @notice Interface for contracts that want to receive ERC-721 tokens safely.
interface IERC721Receiver {
    /// @notice Handle the receipt of an NFT.
    /// @dev The ERC-721 smart contract calls this function on the recipient after a `safeTransfer`.
    /// @return `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))` to confirm receipt.
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}
