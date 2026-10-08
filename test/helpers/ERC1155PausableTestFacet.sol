// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1155PausableLib} from "@lattice/tokens/ERC1155/libraries/ERC1155PausableLib.sol";

/// @title ERC1155PausableTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet that mints through {ERC1155PausableLib}, the path a production mint facet on a
///         pausable diamond must use. It has the same `mint`/`mintBatch` signatures as {ERC1155TestFacet}, which
///         mints through the base {ERC1155Lib} and ignores the pause. Cut on top of the {DeployERC1155Pausable}
///         recipe; never shipped.
contract ERC1155PausableTestFacet {
    function mint(address to, uint256 id, uint256 value, bytes calldata data) external {
        ERC1155PausableLib._mint(to, id, value, data);
    }

    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external {
        ERC1155PausableLib._mintBatch(to, ids, values, data);
    }
}
