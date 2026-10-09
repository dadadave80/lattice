// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC1155Supply
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/extensions/ERC1155Supply.sol)
/// @notice Supply views of the ERC-1155 supply-tracking extension. OpenZeppelin ships no interface for this
///         extension; Lattice declares one so diamonds can advertise it through ERC-165. The facet also serves
///         `burn`/`burnBatch`, which belong to `IERC1155Burnable` and are left out here.
interface IERC1155Supply {
    /// @notice Total value of tokens of type `id` in existence.
    function totalSupply(uint256 id) external view returns (uint256);

    /// @notice Total value of tokens across every id.
    /// @dev Bounded by `type(uint256).max`: a mint that would push it past that reverts.
    function totalSupply() external view returns (uint256);

    /// @notice Whether any token of type `id` exists, that is `totalSupply(id) > 0`.
    function exists(uint256 id) external view returns (bool);
}
