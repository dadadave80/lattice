// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ERC20BurnableLib} from "@lattice/tokens/ERC20/libraries/ERC20BurnableLib.sol";
import {ERC20CappedLib} from "@lattice/tokens/ERC20/libraries/ERC20CappedLib.sol";
import {ERC20FlashMintLib} from "@lattice/tokens/ERC20/libraries/ERC20FlashMintLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

/// @title ComposedTokenInit
/// @notice One-shot initializer for the composed ERC-20 diamond (mirrors {AccountInit}). Delegatecalled by the
///         proxy's `diamondCut` during {Diamond.initialize}, so `address(this)` is the diamond and each `__*_init`
///         runs in its storage. No own pre/postInitializer — {Diamond.initialize} already wraps this in the
///         initializing window, so the `checkInitializing` guard inside each `__*_init` passes.
contract ComposedTokenInit {
    function init(uint256 cap) external {
        ERC20Lib.__ERC20_init("Composed", "CMP");
        ERC20BurnableLib.__ERC20Burnable_init();
        ERC20CappedLib.__ERC20Capped_init(cap);
        ERC20FlashMintLib.__ERC20FlashMint_init();
        PausableLib.__Pausable_init();
    }
}

/// @title ComposedTokenTestFacet
/// @notice Test-only facet supplying the two entrypoints the composed token needs that no production facet
///         exposes: a cap-enforced `mint` (production minting is app-specific/access-gated) and an unguarded
///         `pauseIt` (production pause is admin-gated via the {Pausable} facet). It is the diamond-facet analog of
///         the `mint`/`pauseIt` helpers on the old flattened `ComposedToken` mock.
contract ComposedTokenTestFacet {
    function mint(address to, uint256 amount) external {
        ERC20CappedLib._checkCap(ERC20Lib.totalSupply() + amount);
        ERC20Lib._mint(to, amount);
    }

    function pauseIt() external {
        PausableLib._pause();
    }
}
