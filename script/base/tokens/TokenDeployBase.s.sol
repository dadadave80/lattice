// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {ERC1155Init} from "@lattice/tokens/ERC1155/ERC1155Init.sol";
import {ERC20Init} from "@lattice/tokens/ERC20/ERC20Init.sol";
import {ERC721Init} from "@lattice/tokens/ERC721/ERC721Init.sol";

/// @title TokenDeployBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Shared internal token-base builders used by canonical tokens and their extension recipes.
abstract contract TokenDeployBase is BaseDeploy {
    /// @dev Shared token-base builders run internally. Deploying a recipe helper during broadcast would
    ///      put script code and its cheatcode-dependent buildCuts call on-chain (and can exceed EIP-170).
    function _erc20Base(string memory name, string memory symbol)
        internal
        returns (FacetCut[] memory cuts, address init, bytes memory data)
    {
        cuts = _baseTokenCuts("ERC20");
        (init, data) = _withImmutableIntrospection(_init("ERC20Init"), abi.encodeCall(ERC20Init.init, (name, symbol)));
    }

    function _erc721Base(string memory name, string memory symbol)
        internal
        returns (FacetCut[] memory cuts, address init, bytes memory data)
    {
        cuts = _baseTokenCuts("ERC721");
        (init, data) = _withImmutableIntrospection(_init("ERC721Init"), abi.encodeCall(ERC721Init.init, (name, symbol)));
    }

    function _erc1155Base(string memory uri)
        internal
        returns (FacetCut[] memory cuts, address init, bytes memory data)
    {
        cuts = _baseTokenCuts("ERC1155");
        (init, data) = _withImmutableIntrospection(_init("ERC1155Init"), abi.encodeCall(ERC1155Init.init, (uri)));
    }

    function _baseTokenCuts(string memory module) internal returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](3);
        cuts[0] = _cut(_facet("ERC165Facet"));
        cuts[1] = _cut(_facet(module));
        cuts[2] = _cut(_facet("DiamondLoupeFacet"));
    }
}
