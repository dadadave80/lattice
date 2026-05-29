// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1155Lib} from "@lattice/tokens/libraries/ERC1155Lib.sol";
import {IERC1155} from "@lattice/interfaces/IERC1155.sol";

/// @title ERC1155
/// @notice Stateless Diamond facet for the ERC-1155 Multi-Token Standard.
/// @dev All logic lives in ERC1155Lib. This contract is a pure delegator.
contract ERC1155 is IERC1155 {
    /// @inheritdoc IERC1155
    function uri(uint256 id) public view virtual returns (string memory) {
        return ERC1155Lib.uri(id);
    }

    /// @inheritdoc IERC1155
    function balanceOf(address account, uint256 id) public view virtual returns (uint256) {
        return ERC1155Lib.balanceOf(account, id);
    }

    /// @inheritdoc IERC1155
    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        public
        view
        virtual
        returns (uint256[] memory)
    {
        return ERC1155Lib.balanceOfBatch(accounts, ids);
    }

    /// @inheritdoc IERC1155
    function isApprovedForAll(address account, address operator) public view virtual returns (bool) {
        return ERC1155Lib.isApprovedForAll(account, operator);
    }

    /// @inheritdoc IERC1155
    function setApprovalForAll(address operator, bool approved) public virtual {
        ERC1155Lib.setApprovalForAll(operator, approved);
    }

    /// @inheritdoc IERC1155
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data)
        public
        virtual
    {
        ERC1155Lib.safeTransferFrom(from, to, id, value, data);
    }

    /// @inheritdoc IERC1155
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) public virtual {
        ERC1155Lib.safeBatchTransferFrom(from, to, ids, values, data);
    }
}
