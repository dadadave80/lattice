// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ERC20BurnableLib} from "@lattice/tokens/ERC20/libraries/ERC20BurnableLib.sol";
import {ERC20CappedLib} from "@lattice/tokens/ERC20/libraries/ERC20CappedLib.sol";
import {ERC20FlashMintLib} from "@lattice/tokens/ERC20/libraries/ERC20FlashMintLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC20PermitLib} from "@lattice/tokens/ERC20/libraries/ERC20PermitLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

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

/// @title PermitTokenInit
/// @notice Initializer for a composed PERMIT token diamond. Seeds the ERC-20, EIP-712 domain, nonce, and ERC-2612
///         storage once. The EIP-712 domain is shared storage that both {ERC20Permit} (to build the digest) and the
///         standalone {EIP712} facet (for `eip712Domain()` discovery) read — neither owns that facet via inheritance.
contract PermitTokenInit {
    function init() external {
        ERC20Lib.__ERC20_init("Permit", "PRMT");
        EIP712Lib.__EIP712_init("Permit", "1");
        NoncesLib.__Nonces_init();
        ERC20PermitLib.__ERC20Permit_init();
    }
}
