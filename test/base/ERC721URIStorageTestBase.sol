// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC721URIStorage} from "@lattice-script/base/tokens/DeployERC721URIStorage.s.sol";
import {ERC721TestFacet} from "@lattice-test/helpers/ERC721TestFacet.sol";
import {ERC721URIStorage} from "@lattice/tokens/ERC721/ERC721URIStorage.sol";

/// @title ERC721URIStorageTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ERC-721 per-token-URI (EIP-4906) facet tests, exercising a REAL {Diamond} rather than a
///         flattened inheritance mock. `setUp` assembles the production {DeployERC721URIStorage} recipe
///         (ERC165 + ERC721URIStorage + AccessControl, seeded by {ERC721Init} + {ERC721URIStorageInit} via
///         {MultiInit}) and appends a test-only {ERC721TestFacet} for mint/burn + direct URI seeding — so
///         every standard/extension call routes through the diamond's `delegatecall` dispatch.
/// @dev The URI-storage facet subsumes the base ERC-721 facet (it inherits {ERC721}), so this is its own
///      three-facet recipe rather than a base ERC-721 diamond with an appended cut (an append would collide on
///      the inherited selectors). Uses {MultiInit} directly to keep the appended helper cut in the same
///      initializing window as the production initializers.
abstract contract ERC721URIStorageTestBase is GetSelectors {
    DeployERC721URIStorage internal deployer;
    address internal diamond; // the assembled URI-storage ERC-721 token diamond
    ERC721URIStorage internal token; // typed handle (standard + URI-storage calls dispatch through it)
    ERC721TestFacet internal helper; // typed handle for test-only mint/burn + direct URI seeding
    address internal admin; // holds DEFAULT_ADMIN_ROLE (may call the facet's admin-gated setTokenURI)

    /// @notice Assembles the production URI-storage ERC-721 diamond + the test helper facet.
    /// @param name_ Token name. @param symbol_ Token symbol. @param admin_ The metadata admin.
    /// @return diamond_ The deployed token diamond.
    function _deployERC721URIStorage(string memory name_, string memory symbol_, address admin_)
        internal
        returns (address diamond_)
    {
        deployer = new DeployERC721URIStorage();
        (FacetCut[] memory prod, address[] memory inits, bytes[] memory initCalldatas) =
            deployer.buildCuts(name_, symbol_, admin_);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new ERC721TestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("ERC721TestFacet")
        });

        MultiInit multiInit = new MultiInit();
        Diamond d = new Diamond();
        d.initialize(cuts, address(multiInit), abi.encodeCall(MultiInit.multiInit, (inits, initCalldatas)));
        diamond_ = address(d);
    }

    function setUp() public virtual {
        admin = address(0xA);
        diamond = _deployERC721URIStorage("Test NFT URI", "TNFTU", admin);
        token = ERC721URIStorage(diamond);
        helper = ERC721TestFacet(diamond);
    }
}
