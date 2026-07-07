// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC1155} from "@lattice-script/base/tokens/DeployERC1155.s.sol";
import {ERC1155TestFacet} from "@lattice-test/helpers/ERC1155TestFacet.sol";
import {ERC1155} from "@lattice/tokens/ERC1155/ERC1155.sol";

/// @title ERC1155TestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ERC-1155 facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployERC1155} recipe (ERC165 + ERC1155 + {ERC1155Init}) and
///         appends a test-only {ERC1155TestFacet} for balance seeding — so every standard call in a subclass
///         test routes through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock
///         hides.
/// @dev Extension-token tests override `setUp` to pass their additive facet cuts via
///      `_deployERC1155(.., extraCuts)` (base ERC-1155 needs only the single {ERC1155Init}; facets requiring
///      their own init compose via MultiInit — see {BaseDeploy._assembleMulti}).
abstract contract ERC1155TestBase is GetSelectors {
    DeployERC1155 internal deployer;
    address internal diamond; // the assembled ERC-1155 token diamond
    ERC1155 internal token; // typed handle on the diamond (standard ERC-1155 calls dispatch through it)
    ERC1155TestFacet internal helper; // typed handle for test-only mint/mintBatch/burn

    /// @notice Assembles the production ERC-1155 diamond + the test helper facet (+ any `extraCuts`).
    /// @param uri_ Token URI template.
    /// @param extraCuts Additional facet cuts (extension facets) appended after the base recipe.
    /// @return diamond_ The deployed token diamond.
    function _deployERC1155(string memory uri_, FacetCut[] memory extraCuts) internal returns (address diamond_) {
        deployer = new DeployERC1155();
        (FacetCut[] memory prod, address init, bytes memory initCalldata) = deployer.buildCuts(uri_);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1 + extraCuts.length);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new ERC1155TestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("ERC1155TestFacet")
        });
        for (uint256 j; j < extraCuts.length; ++j) {
            cuts[prod.length + 1 + j] = extraCuts[j];
        }

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }

    function setUp() public virtual {
        diamond = _deployERC1155("https://example.com/{id}", new FacetCut[](0));
        token = ERC1155(diamond);
        helper = ERC1155TestFacet(diamond);
    }
}
