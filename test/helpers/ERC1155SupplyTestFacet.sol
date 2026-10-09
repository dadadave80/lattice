// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1155SupplyLib} from "@lattice/tokens/ERC1155/libraries/ERC1155SupplyLib.sol";

/// @title ERC1155SupplyTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet that mints through {ERC1155SupplyLib}, the path a production mint facet on a
///         supply-tracked diamond must use. It has the same `mint`/`mintBatch` signatures as {ERC1155TestFacet},
///         which mints through the base {ERC1155Lib} and would leave the supply counters behind. Cut on top of
///         the {DeployERC1155Supply} recipe; never shipped.
contract ERC1155SupplyTestFacet {
    function mint(address to, uint256 id, uint256 value, bytes calldata data) external {
        ERC1155SupplyLib._mint(to, id, value, data);
    }

    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external {
        ERC1155SupplyLib._mintBatch(to, ids, values, data);
    }
}
