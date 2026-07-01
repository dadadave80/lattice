// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

/// @title TokenTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet that exposes the internal ERC-20 mint/burn the production facets deliberately gate
///         (production minting is app-specific / access-controlled). It is cut ON TOP of the production
///         {DeployERC20} recipe so a facet test can seed balances while still exercising the REAL diamond
///         dispatch for every standard call — never shipped, never part of a `run()` deploy.
contract TokenTestFacet {
    function mint(address to, uint256 amount) external {
        ERC20Lib._mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        ERC20Lib._burn(from, amount);
    }
}
