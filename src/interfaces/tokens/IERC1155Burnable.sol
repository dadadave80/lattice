// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC1155Burnable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/extensions/ERC1155Burnable.sol)
/// @notice Interface for burnable ERC-1155 tokens. The burns revert with the {IERC1155} errors and emit the
///         {IERC1155} transfer events with `to == address(0)`.
interface IERC1155Burnable {
    /// @notice Destroys `value` tokens of type `id` from `account`.
    /// @dev The caller must be `account` or an operator approved by `account`.
    function burn(address account, uint256 id, uint256 value) external;

    /// @notice Batched version of {burn}.
    /// @dev The caller must be `account` or an operator approved by `account`.
    function burnBatch(address account, uint256[] calldata ids, uint256[] calldata values) external;
}
