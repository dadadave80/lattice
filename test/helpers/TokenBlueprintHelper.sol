// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ComposedTokenInit, ComposedTokenTestFacet} from "@lattice-test/composability/ComposedTokenInit.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Burnable} from "@lattice/tokens/ERC20/ERC20Burnable.sol";
import {ERC20Capped} from "@lattice/tokens/ERC20/ERC20Capped.sol";
import {ERC20FlashMint} from "@lattice/tokens/ERC20/ERC20FlashMint.sol";
import {ERC20Pausable} from "@lattice/tokens/ERC20/ERC20Pausable.sol";

/// @notice Assembles a maximally-composed ERC-20 token diamond from real facet cuts — the token analog of
///         {AccountBlueprintHelper}. Base `ERC20` plus the `Burnable`/`Capped`/`FlashMint` additive extensions are
///         `Add`ed; `ERC20Pausable` is `Replace`d over the base's `transfer`/`transferFrom` (which must pre-exist,
///         hence ERC20 is `Add`ed first). A real diamond cut here proves the de-inherited extensions own disjoint
///         selectors — a regression that re-exports a base selector makes the `Add` revert
///         `CannotAddFunctionToDiamondThatAlreadyExists`. Selectors come from diamond-lib `GetSelectors`
///         (`forge inspect` over FFI).
abstract contract TokenBlueprintHelper is GetSelectors {
    /// @return cuts The facet cuts (Add base+additive, Replace Pausable) wiring a composed ERC-20 token.
    /// @return init The matching initializer (`init(uint256 cap)`).
    function _composedErc20Blueprint() internal returns (FacetCut[] memory cuts, ComposedTokenInit init) {
        cuts = new FacetCut[](7);
        cuts[0] = _add(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _add(address(new ERC20()), "ERC20");
        cuts[2] = _add(address(new ERC20Burnable()), "ERC20Burnable");
        cuts[3] = _add(address(new ERC20Capped()), "ERC20Capped");
        cuts[4] = _add(address(new ERC20FlashMint()), "ERC20FlashMint");
        cuts[5] = _add(address(new ComposedTokenTestFacet()), "ComposedTokenTestFacet");
        cuts[6] = _replace(address(new ERC20Pausable()), "ERC20Pausable");
        init = new ComposedTokenInit();
    }

    function _add(address facet, string memory name) private returns (FacetCut memory) {
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: _getSelectors(name)});
    }

    function _replace(address facet, string memory name) private returns (FacetCut memory) {
        return FacetCut({facetAddress: facet, action: FacetCutAction.Replace, functionSelectors: _getSelectors(name)});
    }
}
