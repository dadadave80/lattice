// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC721} from "@lattice-script/base/tokens/DeployERC721.s.sol";
import {ERC721TestFacet} from "@lattice-test/helpers/ERC721TestFacet.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";

/// @title ERC721TestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ERC-721 facet tests that exercise a REAL {Diamond} rather than a flattened inheritance mock.
///         `setUp` assembles the production {DeployERC721} recipe (ERC165 + ERC721 + {ERC721Init}) and appends a
///         test-only {ERC721TestFacet} for mint/burn/transfer seeding — so every standard call in a subclass
///         test routes through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a
///         mock hides.
/// @dev Extension-token tests pass their additive facet cuts via `_deployERC721(.., extraCuts)` (base ERC-721
///      needs only the single {ERC721Init}; facets requiring their own init compose via MultiInit — see
///      {BaseDeploy._assembleMulti} and {ERC721URIStorageTestBase}).
abstract contract ERC721TestBase is GetSelectors {
    DeployERC721 internal deployer;
    address internal diamond; // the assembled ERC-721 token diamond
    ERC721 internal token; // typed handle on the diamond (standard ERC-721 calls dispatch through it)
    ERC721TestFacet internal helper; // typed handle for test-only mint/burn/transfer

    /// @notice Assembles the production ERC-721 diamond + the test helper facet (+ any `extraCuts`).
    /// @param name_ Token name. @param symbol_ Token symbol.
    /// @param extraCuts Additional facet cuts (extension facets) appended after the base recipe.
    /// @return diamond_ The deployed token diamond.
    function _deployERC721(string memory name_, string memory symbol_, FacetCut[] memory extraCuts)
        internal
        returns (address diamond_)
    {
        deployer = new DeployERC721();
        (FacetCut[] memory prod, address init, bytes memory initCalldata) = deployer.buildCuts(name_, symbol_);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1 + extraCuts.length);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new ERC721TestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("ERC721TestFacet")
        });
        for (uint256 j; j < extraCuts.length; ++j) {
            cuts[prod.length + 1 + j] = extraCuts[j];
        }

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }

    function setUp() public virtual {
        diamond = _deployERC721("Test NFT", "TNFT", new FacetCut[](0));
        token = ERC721(diamond);
        helper = ERC721TestFacet(diamond);
    }
}
