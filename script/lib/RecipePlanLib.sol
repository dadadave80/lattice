// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {RecipeFacet, RecipeSeam, RecipeSelectorSelection} from "@lattice-script/lib/RecipeSpec.sol";

/// @title RecipePlanLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Pure script-only declarations and early compatibility checks shared by checked recipe builders.
library RecipePlanLib {
    error UnknownRecipeFacet(string name);
    error IncompatibleRecipeFacets(string facet, string incompatibleFacet);
    error InvalidRecipeSelection(string facet, bytes4 selector);
    error UndeclaredRecipeSeam(string facet, bytes4 selector);
    error InvalidRecipeCut(string facet, bytes4 selector, FacetCutAction action);
    error InvalidRecipeSeam(string seam);
    error MissingRecipeSeamRoute(string seam, bytes4 selector);
    error WrongRecipeSeamOwner(string seam, bytes4 selector, string owner);

    function all(string memory name) internal pure returns (RecipeFacet memory) {
        return RecipeFacet(name, FacetCutAction.Add, RecipeSelectorSelection.All, new bytes4[](0));
    }

    function except(string memory name, bytes4[] memory selectors) internal pure returns (RecipeFacet memory) {
        return RecipeFacet(name, FacetCutAction.Add, RecipeSelectorSelection.Except, selectors);
    }

    function replaceAll(string memory name) internal pure returns (RecipeFacet memory) {
        return RecipeFacet(name, FacetCutAction.Replace, RecipeSelectorSelection.All, new bytes4[](0));
    }

    function only(string memory name, FacetCutAction action, bytes4[] memory selectors)
        internal
        pure
        returns (RecipeFacet memory)
    {
        return RecipeFacet(name, action, RecipeSelectorSelection.Only, selectors);
    }

    function append(RecipeFacet[] memory base, RecipeFacet[] memory extension)
        internal
        pure
        returns (RecipeFacet[] memory facets)
    {
        facets = new RecipeFacet[](base.length + extension.length);
        for (uint256 i; i < base.length; ++i) {
            facets[i] = base[i];
        }
        for (uint256 i; i < extension.length; ++i) {
            facets[base.length + i] = extension[i];
        }
    }

    function seam2(
        string memory id,
        bytes4 selector,
        string memory first,
        string memory second,
        string memory owner,
        string memory reason
    ) internal pure returns (RecipeSeam memory seam) {
        seam.id = id;
        seam.selector = selector;
        seam.participants = new string[](2);
        seam.participants[0] = first;
        seam.participants[1] = second;
        seam.allowedOwners = new string[](1);
        seam.allowedOwners[0] = owner;
        seam.reason = reason;
    }

    function seam3(
        string memory id,
        bytes4 selector,
        string memory first,
        string memory second,
        string memory third,
        string memory owner,
        string memory reason
    ) internal pure returns (RecipeSeam memory seam) {
        seam = seam2(id, selector, first, second, owner, reason);
        seam.participants = new string[](3);
        seam.participants[0] = first;
        seam.participants[1] = second;
        seam.participants[2] = third;
    }

    /// @dev Run before resolving even one released facet or initializer. This is a checked-script policy,
    ///      not a restriction on arbitrary diamondCut calldata. ERC1363 directly moves through ERC20Lib;
    ///      these other movers require mutually exclusive movement paths under ADR0009.
    function validateEarly(RecipeFacet[] memory facets, RecipeSeam[] memory seams) internal pure {
        (string[] memory names,) = FacetInventory.inventory();
        for (uint256 i; i < facets.length; ++i) {
            if (!_containsName(names, facets[i].name)) revert UnknownRecipeFacet(facets[i].name);
        }
        for (uint256 i; i < seams.length; ++i) {
            RecipeSeam memory seam = seams[i];
            if (
                bytes(seam.id).length == 0 || bytes(seam.reason).length == 0 || seam.participants.length < 2
                    || (seam.allowedOwners.length == 0 && !seam.allowUnrouted)
            ) revert InvalidRecipeSeam(seam.id);
            for (uint256 j; j < seam.participants.length; ++j) {
                if (!_containsName(names, seam.participants[j])) revert UnknownRecipeFacet(seam.participants[j]);
            }
            for (uint256 j; j < seam.allowedOwners.length; ++j) {
                if (!_containsName(names, seam.allowedOwners[j])) revert UnknownRecipeFacet(seam.allowedOwners[j]);
            }
        }
        if (!contains(facets, "ERC1363")) return;
        // The reconciler is a distinct incompatibility even though its canonical recipe also installs Votes.
        if (contains(facets, "GovernedVault")) revert IncompatibleRecipeFacets("ERC1363", "GovernedVault");
        if (contains(facets, "ERC20Pausable")) revert IncompatibleRecipeFacets("ERC1363", "ERC20Pausable");
        if (contains(facets, "ERC20Votes")) revert IncompatibleRecipeFacets("ERC1363", "ERC20Votes");
    }

    function contains(RecipeFacet[] memory facets, string memory name) internal pure returns (bool) {
        for (uint256 i; i < facets.length; ++i) {
            if (equal(facets[i].name, name)) return true;
        }
        return false;
    }

    /// @notice Check exported-selector coverage, ordered Add/Replace semantics and final seam ownership.
    /// @dev The builder observes exports only after validateEarly succeeds. This simulation is separate from
    ///      the tests' final IDiamondLoupe observations, which catch wrong routing on a real assembled proxy.
    function validateCuts(
        RecipeFacet[] memory facets,
        RecipeSeam[] memory seams,
        FacetCut[] memory cuts,
        bytes4[][] memory exports
    ) internal pure {
        uint256 maximum;
        for (uint256 i; i < cuts.length; ++i) {
            maximum += cuts[i].functionSelectors.length;
        }
        bytes4[] memory selectors = new bytes4[](maximum);
        uint256[] memory owners = new uint256[](maximum);
        uint256 used;
        for (uint256 i; i < facets.length; ++i) {
            RecipeFacet memory facet = facets[i];
            if (cuts[i].functionSelectors.length == 0 || cuts[i].action == FacetCutAction.Remove) {
                revert InvalidRecipeCut(facet.name, bytes4(0), cuts[i].action);
            }
            for (uint256 j; j < cuts[i].functionSelectors.length; ++j) {
                bytes4 selector = cuts[i].functionSelectors[j];
                if (!_containsSelector(exports[i], selector)) revert InvalidRecipeSelection(facet.name, selector);
                uint256 at = _routeIndex(selectors, used, selector);
                if (cuts[i].action == FacetCutAction.Add) {
                    if (at != type(uint256).max) revert InvalidRecipeCut(facet.name, selector, cuts[i].action);
                    selectors[used] = selector;
                    owners[used++] = i;
                } else {
                    if (at == type(uint256).max || equal(facets[owners[at]].name, facet.name)) {
                        revert InvalidRecipeCut(facet.name, selector, cuts[i].action);
                    }
                    _requireSeam(facets, seams, facet.name, selector);
                    owners[at] = i;
                }
            }
            if (facet.selection == RecipeSelectorSelection.Except) {
                for (uint256 j; j < facet.selectors.length; ++j) {
                    if (!_containsSelector(exports[i], facet.selectors[j])) {
                        revert InvalidRecipeSelection(facet.name, facet.selectors[j]);
                    }
                    _requireSeam(facets, seams, facet.name, facet.selectors[j]);
                }
            }
            // A split Add/Replace cut is one facet surface. Only selectors omitted from the union need
            // an exclusion declaration; all Replace selectors already need their own active seam above.
            for (uint256 j; j < exports[i].length; ++j) {
                if (!_facetSelects(facets, cuts, facet.name, exports[i][j])) {
                    _requireSeam(facets, seams, facet.name, exports[i][j]);
                }
            }
        }
        for (uint256 i; i < seams.length; ++i) {
            RecipeSeam memory seam = seams[i];
            if (!_active(facets, seam)) continue;
            if (bytes(seam.id).length == 0 || bytes(seam.reason).length == 0 || seam.participants.length < 2) {
                revert InvalidRecipeSeam(seam.id);
            }
            uint256 at = _routeIndex(selectors, used, seam.selector);
            if (at == type(uint256).max) {
                if (!seam.allowUnrouted) revert MissingRecipeSeamRoute(seam.id, seam.selector);
                continue;
            }
            string memory owner = facets[owners[at]].name;
            if (!_containsName(seam.allowedOwners, owner)) {
                revert WrongRecipeSeamOwner(seam.id, seam.selector, owner);
            }
        }
    }

    function _requireSeam(RecipeFacet[] memory facets, RecipeSeam[] memory seams, string memory facet, bytes4 selector)
        private
        pure
    {
        for (uint256 i; i < seams.length; ++i) {
            if (
                seams[i].selector == selector && _containsName(seams[i].participants, facet)
                    && _active(facets, seams[i])
            ) return;
        }
        revert UndeclaredRecipeSeam(facet, selector);
    }

    function _facetSelects(RecipeFacet[] memory facets, FacetCut[] memory cuts, string memory facet, bytes4 selector)
        private
        pure
        returns (bool)
    {
        for (uint256 i; i < facets.length; ++i) {
            if (equal(facets[i].name, facet) && _containsSelector(cuts[i].functionSelectors, selector)) return true;
        }
        return false;
    }

    function _active(RecipeFacet[] memory facets, RecipeSeam memory seam) private pure returns (bool) {
        for (uint256 i; i < seam.participants.length; ++i) {
            if (!contains(facets, seam.participants[i])) return false;
        }
        return true;
    }

    function _containsName(string[] memory names, string memory name) private pure returns (bool) {
        for (uint256 i; i < names.length; ++i) {
            if (equal(names[i], name)) return true;
        }
        return false;
    }

    function _containsSelector(bytes4[] memory selectors, bytes4 selector) private pure returns (bool) {
        for (uint256 i; i < selectors.length; ++i) {
            if (selectors[i] == selector) return true;
        }
        return false;
    }

    function _routeIndex(bytes4[] memory selectors, uint256 used, bytes4 selector) private pure returns (uint256) {
        for (uint256 i; i < used; ++i) {
            if (selectors[i] == selector) return i;
        }
        return type(uint256).max;
    }

    function equal(string memory left, string memory right) internal pure returns (bool) {
        return keccak256(bytes(left)) == keccak256(bytes(right));
    }
}
