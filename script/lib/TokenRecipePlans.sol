// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RecipePlanLib} from "@lattice-script/lib/RecipePlanLib.sol";
import {RecipeFacet} from "@lattice-script/lib/RecipeSpec.sol";

/// @title TokenRecipePlans
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The three canonical token-base cut plans, reused by their recipes and additive extensions.
library TokenRecipePlans {
    function erc20(bool admin) internal pure returns (RecipeFacet[] memory) {
        return _base("ERC20", admin);
    }

    function erc721(bool admin) internal pure returns (RecipeFacet[] memory) {
        return _base("ERC721", admin);
    }

    function erc1155(bool admin) internal pure returns (RecipeFacet[] memory) {
        return _base("ERC1155", admin);
    }

    function _base(string memory module, bool admin) private pure returns (RecipeFacet[] memory facets) {
        facets = new RecipeFacet[](admin ? 5 : 3);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all(module);
        facets[2] = RecipePlanLib.all("DiamondLoupeFacet");
        if (admin) {
            facets[3] = RecipePlanLib.all("AccessControl");
            facets[4] = RecipePlanLib.all("AccessControlDiamondCut");
        }
    }
}
