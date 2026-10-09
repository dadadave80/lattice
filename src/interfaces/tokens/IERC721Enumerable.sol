// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC721Enumerable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/IERC721Enumerable.sol)
/// @notice The optional EIP-721 enumeration extension. Its interfaceId is `0x780e9d63`, the canonical EIP-721 id.
/// @dev Unlike OpenZeppelin's, it does not inherit {IERC721}. Lattice's {IERC721} bundles the metadata functions
///      (#222), and keeping this interface standalone keeps its ABI to the three enumeration functions. The
///      `ERC721OutOfBoundsIndex` and `ERC721EnumerableForbiddenBatchMint` errors, which OpenZeppelin declares on the
///      contract, live here.
interface IERC721Enumerable {
    /// @notice An `owner`'s token query was out of bounds for `index`. A zero `owner` means the global index.
    error ERC721OutOfBoundsIndex(address owner, uint256 index);

    /// @notice Batch mints ({ERC721ConsecutiveLib}) and enumeration cannot share a diamond: a batch skips the
    ///         enumeration lists.
    error ERC721EnumerableForbiddenBatchMint();

    /// @notice The number of tokens in existence.
    function totalSupply() external view returns (uint256);

    /// @notice The id of the token at `index` of `owner`'s token list. Use with `balanceOf` to enumerate them.
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    /// @notice The id of the token at `index` of all tokens. Use with {totalSupply} to enumerate them.
    function tokenByIndex(uint256 index) external view returns (uint256);
}
