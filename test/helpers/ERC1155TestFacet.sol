// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1155Lib} from "@lattice/tokens/ERC1155/libraries/ERC1155Lib.sol";

/// @title ERC1155TestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet that exposes the internal ERC-1155 mint/mintBatch/burn the production facets
///         deliberately gate (production minting is app-specific / access-controlled). It is cut ON TOP of the
///         production {DeployERC1155} recipe so a facet test can seed balances while still exercising the REAL
///         diamond dispatch for every standard call — never shipped, never part of a `run()` deploy.
contract ERC1155TestFacet {
    function mint(address to, uint256 id, uint256 value, bytes calldata data) external {
        ERC1155Lib._mint(to, id, value, data);
    }

    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external {
        ERC1155Lib._mintBatch(to, ids, values, data);
    }

    function burn(address from, uint256 id, uint256 value) external {
        ERC1155Lib._burn(from, id, value);
    }
}
