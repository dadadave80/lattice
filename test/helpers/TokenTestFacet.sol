// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20CappedLib} from "@lattice/tokens/ERC20/libraries/ERC20CappedLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC20WrapperLib} from "@lattice/tokens/ERC20/libraries/ERC20WrapperLib.sol";

/// @title TokenTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet that exposes the internal ERC-20 lib entrypoints the production facets deliberately
///         gate (production minting is app-specific / access-controlled). It is cut ON TOP of the production
///         {DeployERC20} (or an extension) recipe so a facet test can seed balances while still exercising the
///         REAL diamond dispatch for every standard call — never shipped, never part of a `run()` deploy.
/// @dev `cappedMint` mirrors the (internal) {ERC20Capped._mint}: it runs the real {ERC20CappedLib._checkCap}
///      cap guard before minting, so the capped facet test enforces the cap through the diamond. `recover` exposes
///      the access-controlled {ERC20WrapperLib.recover}. Both revert exactly as their libraries do.
contract TokenTestFacet {
    function mint(address to, uint256 amount) external {
        ERC20Lib._mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        ERC20Lib._burn(from, amount);
    }

    /// @notice Cap-enforcing mint for the {ERC20Capped} facet test (reverts with `ERC20ExceededCap` past the cap).
    function cappedMint(address to, uint256 value) external {
        ERC20CappedLib._checkCap(ERC20Lib.totalSupply() + value);
        ERC20Lib._mint(to, value);
    }

    /// @notice Exposes the {ERC20Wrapper} recover() (mints wrapped tokens covering an underlying surplus).
    function recover(address account) external returns (uint256) {
        return ERC20WrapperLib.recover(account);
    }
}
