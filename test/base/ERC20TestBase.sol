// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";

/// @title ERC20TestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ERC-20 facet tests that exercise a REAL {Diamond} rather than a flattened inheritance mock.
///         `setUp` assembles the production {DeployERC20} recipe (ERC165 + ERC20 + {ERC20Init}) and appends a
///         test-only {TokenTestFacet} for balance seeding — so every standard call in a subclass test routes
///         through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides.
/// @dev Extension-token tests build their production recipe from a ready-to-deploy `DeployERC20<Ext>.buildCuts`
///      (which returns the full cut set + the ordered initializer list), then call {_deployWithHelper} to append
///      the {TokenTestFacet} and assemble the diamond running every initializer in one window via {MultiInit}
///      (the same composition {BaseDeploy._assembleMulti} performs in production). Additive extensions
///      (Burnable/FlashMint) append their facet cut; override extensions (Pausable/Wrapper) `Replace` selectors.
abstract contract ERC20TestBase is GetSelectors {
    DeployERC20 internal deployer;
    address internal diamond; // the assembled ERC-20 token diamond
    ERC20 internal token; // typed handle on the diamond (standard ERC-20 calls dispatch through it)
    TokenTestFacet internal helper; // typed handle for test-only mint/burn

    /// @notice Builds the test-only {TokenTestFacet} cut appended on top of every production recipe.
    function _helperCut() internal returns (FacetCut memory) {
        return FacetCut({
            facetAddress: address(new TokenTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("TokenTestFacet")
        });
    }

    /// @notice Assembles the production ERC-20 diamond + the test helper facet (+ any `extraCuts`).
    /// @param name_ Token name. @param symbol_ Token symbol.
    /// @param extraCuts Additional facet cuts (extension facets) appended after the base recipe.
    /// @return diamond_ The deployed token diamond.
    function _deployERC20(string memory name_, string memory symbol_, FacetCut[] memory extraCuts)
        internal
        returns (address diamond_)
    {
        deployer = new DeployERC20();
        (FacetCut[] memory prod, address init, bytes memory initCalldata) = deployer.buildCuts(name_, symbol_);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1 + extraCuts.length);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = _helperCut();
        for (uint256 j; j < extraCuts.length; ++j) {
            cuts[prod.length + 1 + j] = extraCuts[j];
        }

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }

    /// @notice Assembles an extension recipe (`prodCuts` + its ordered `inits`) with the test helper facet cut
    ///         appended, running every initializer in ONE initializing window via {MultiInit} — exactly the
    ///         composition {BaseDeploy._assembleMulti} performs in production.
    /// @param prodCuts The production facet cuts from a `DeployERC20<Ext>.buildCuts`.
    /// @param inits The ordered initializer contracts.
    /// @param initCalldatas The calldata matching each initializer.
    /// @return diamond_ The deployed extension token diamond.
    function _deployWithHelper(FacetCut[] memory prodCuts, address[] memory inits, bytes[] memory initCalldatas)
        internal
        returns (address diamond_)
    {
        FacetCut[] memory cuts = new FacetCut[](prodCuts.length + 1);
        for (uint256 i; i < prodCuts.length; ++i) {
            cuts[i] = prodCuts[i];
        }
        cuts[prodCuts.length] = _helperCut();

        MultiInit multiInit = new MultiInit();
        Diamond d = new Diamond();
        d.initialize(cuts, address(multiInit), abi.encodeCall(MultiInit.multiInit, (inits, initCalldatas)));
        diamond_ = address(d);
    }

    function setUp() public virtual {
        diamond = _deployERC20("Test Token", "TEST", new FacetCut[](0));
        token = ERC20(diamond);
        helper = TokenTestFacet(diamond);
    }
}
