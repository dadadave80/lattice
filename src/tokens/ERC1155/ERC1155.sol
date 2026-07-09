// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1155} from "@lattice/interfaces/tokens/IERC1155.sol";
import {ERC1155Lib} from "@lattice/tokens/ERC1155/libraries/ERC1155Lib.sol";

/// @title ERC1155
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/ERC1155.sol)
/// @notice Stateless Diamond facet for the ERC-1155 Multi-Token Standard.
/// @dev All logic lives in ERC1155Lib. This contract is a pure delegator.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
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
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) public virtual {
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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC1155 methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `balanceOf(address,uint256)` 0x00fdd58e
    ///      `balanceOfBatch(address[],uint256[])` 0x4e1273f4
    ///      `isApprovedForAll(address,address)` 0xe985e9c5
    ///      `safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)` 0x2eb2c2d6
    ///      `safeTransferFrom(address,address,uint256,uint256,bytes)` 0xf242432a
    ///      `setApprovalForAll(address,bool)` 0xa22cb465
    ///      `uri(uint256)` 0x0e89341c
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"00fdd58e4e1273f4e985e9c52eb2c2d6f242432aa22cb4650e89341c";
    }
}
