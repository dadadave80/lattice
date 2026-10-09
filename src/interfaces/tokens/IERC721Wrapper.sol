// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC721Wrapper
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Wrapper.sol)
/// @notice Interface for the ERC-721 wrapper extension: deposit underlying ERC-721 tokens to mint wrapped tokens with
///         the same ids, and burn wrapped tokens to withdraw the underlying ones. Its interfaceId is `0xd9e5011d`.
/// @dev The wrapper facet also implements {IERC721Receiver-onERC721Received}, which is left out of this interface
///      (and of its interfaceId) because it belongs to IERC721Receiver. OpenZeppelin does not advertise it either.
interface IERC721Wrapper {
    /// @notice The received ERC-721 token couldn't be wrapped (it is not the underlying collection).
    error ERC721UnsupportedToken(address token);

    /// @notice The address of the underlying ERC-721 collection being wrapped.
    function underlying() external view returns (address);

    /// @notice Pull each of `tokenIds` from the caller's underlying balance and mint the same ids to `account`.
    function depositFor(address account, uint256[] memory tokenIds) external returns (bool);

    /// @notice Burn each of the caller-authorized wrapped `tokenIds` and send the same underlying ids to `account`.
    function withdrawTo(address account, uint256[] memory tokenIds) external returns (bool);
}
