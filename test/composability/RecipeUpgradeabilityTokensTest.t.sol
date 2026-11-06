// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// AUTO-STRUCTURED guard suite — one test per deploy recipe (see RecipeGuards).
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {DeployERC1155} from "@lattice-script/base/tokens/DeployERC1155.s.sol";
import {DeployERC1155Burnable} from "@lattice-script/base/tokens/DeployERC1155Burnable.s.sol";
import {DeployERC1155Pausable} from "@lattice-script/base/tokens/DeployERC1155Pausable.s.sol";
import {DeployERC1155Supply} from "@lattice-script/base/tokens/DeployERC1155Supply.s.sol";
import {DeployERC1155URIStorage} from "@lattice-script/base/tokens/DeployERC1155URIStorage.s.sol";
import {DeployERC1363} from "@lattice-script/base/tokens/DeployERC1363.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {DeployERC20Burnable} from "@lattice-script/base/tokens/DeployERC20Burnable.s.sol";
import {DeployERC20Capped} from "@lattice-script/base/tokens/DeployERC20Capped.s.sol";
import {DeployERC20Crosschain} from "@lattice-script/base/tokens/DeployERC20Crosschain.s.sol";
import {DeployERC20FlashMint} from "@lattice-script/base/tokens/DeployERC20FlashMint.s.sol";
import {DeployERC20Pausable} from "@lattice-script/base/tokens/DeployERC20Pausable.s.sol";
import {DeployERC20Permit} from "@lattice-script/base/tokens/DeployERC20Permit.s.sol";
import {DeployERC20TemporaryApproval} from "@lattice-script/base/tokens/DeployERC20TemporaryApproval.s.sol";
import {DeployERC20Votes} from "@lattice-script/base/tokens/DeployERC20Votes.s.sol";
import {DeployERC20Wrapper} from "@lattice-script/base/tokens/DeployERC20Wrapper.s.sol";
import {DeployERC2981} from "@lattice-script/base/tokens/DeployERC2981.s.sol";
import {DeployERC3643} from "@lattice-script/base/tokens/DeployERC3643.s.sol";
import {DeployERC4626} from "@lattice-script/base/tokens/DeployERC4626.s.sol";
import {DeployERC721} from "@lattice-script/base/tokens/DeployERC721.s.sol";
import {DeployERC721Burnable} from "@lattice-script/base/tokens/DeployERC721Burnable.s.sol";
import {DeployERC721Consecutive} from "@lattice-script/base/tokens/DeployERC721Consecutive.s.sol";
import {DeployERC721Enumerable} from "@lattice-script/base/tokens/DeployERC721Enumerable.s.sol";
import {DeployERC721Pausable} from "@lattice-script/base/tokens/DeployERC721Pausable.s.sol";
import {DeployERC721Royalty} from "@lattice-script/base/tokens/DeployERC721Royalty.s.sol";
import {DeployERC721URIStorage} from "@lattice-script/base/tokens/DeployERC721URIStorage.s.sol";
import {DeployERC721Votes} from "@lattice-script/base/tokens/DeployERC721Votes.s.sol";
import {DeployERC721Wrapper} from "@lattice-script/base/tokens/DeployERC721Wrapper.s.sol";
import {DeployERC7802} from "@lattice-script/base/tokens/DeployERC7802.s.sol";
import {DeployHTSAdapter} from "@lattice-script/base/tokens/DeployHTSAdapter.s.sol";
import {DeployMarketplaceZone} from "@lattice-script/base/tokens/DeployMarketplaceZone.s.sol";
import {RecipeConsistencyGuards} from "@lattice-test/composability/RecipeConsistencyGuards.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ERC1155} from "@lattice/tokens/ERC1155/ERC1155.sol";
import {ERC20Wrapper} from "@lattice/tokens/ERC20/ERC20Wrapper.sol";
import {ERC3643Params} from "@lattice/tokens/ERC3643/ERC3643Params.sol";
import {ERC4626} from "@lattice/tokens/ERC4626/ERC4626.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721Wrapper} from "@lattice/tokens/ERC721/ERC721Wrapper.sol";

/// @title RecipeUpgradeabilityTokensTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Tokens-family recipe guards: every diamond these recipes assemble must be introspectable and
///         either admin-upgradeable or immutable BY DESIGN (never silently frozen).
contract RecipeUpgradeabilityTokensTest is RecipeConsistencyGuards {
    TestnetAsset internal asset;

    function setUp() public {
        asset = new TestnetAsset("Guard Asset", "GA");
    }

    function test_Immutable_ERC20() public {
        _expectRecipe(new DeployERC20().recipeSpec(), 0, "DeployERC20");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC20().buildCuts("Tok", "TOK");
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Immutable_ERC3643() public {
        _assertERC3643Recipe(false);
    }

    function test_Immutable_ERC3643TemporaryApproval() public {
        _assertERC3643Recipe(true);
    }

    function _assertERC3643Recipe(bool temporaryApproval) private {
        ERC3643Params memory config;
        config.owner = address(this);
        config.agents = new address[](0);
        config.name = "Permissioned";
        config.symbol = "PERM";
        config.decimals = 6;
        config.temporaryApproval = temporaryApproval;
        _expectRecipe(new DeployERC3643().recipeSpec(), temporaryApproval ? 1 : 0, "DeployERC3643");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC3643().buildCuts(config);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, temporaryApproval ? 11 : 10);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC20() public {
        _expectRecipe(new DeployERC20().recipeSpec(), 1, "DeployERC20");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC20().buildCuts("Tok", "TOK", ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        assertEq(IERC20(d).name(), "Tok", "module init: ERC20 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC721() public {
        _expectRecipe(new DeployERC721().recipeSpec(), 0, "DeployERC721");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC721().buildCuts("Tok", "TOK");
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC721() public {
        _expectRecipe(new DeployERC721().recipeSpec(), 1, "DeployERC721");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC721().buildCuts("Tok", "TOK", ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        assertEq(ERC721(d).name(), "Tok", "module init: ERC721 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC1155() public {
        _expectRecipe(new DeployERC1155().recipeSpec(), 0, "DeployERC1155");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC1155().buildCuts("uri://");
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC1155() public {
        _expectRecipe(new DeployERC1155().recipeSpec(), 1, "DeployERC1155");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC1155().buildCuts("uri://", ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        assertEq(ERC1155(d).uri(0), "uri://", "module init: ERC1155 uri");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC1155Burnable() public {
        _expectRecipe(new DeployERC1155Burnable().recipeSpec(), 0, "DeployERC1155Burnable");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC1155Burnable().buildCuts("uri://");
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC1155Burnable() public {
        _expectRecipe(new DeployERC1155Burnable().recipeSpec(), 1, "DeployERC1155Burnable");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC1155Burnable().buildCuts("uri://", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(ERC1155(d).uri(0), "uri://", "module init chain: ERC1155 uri");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC1155Pausable() public {
        _expectRecipe(new DeployERC1155Pausable().recipeSpec(), 0, "DeployERC1155Pausable");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC1155Pausable().buildCuts("uri://", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 7);
        _assertBareEth(d, false);
        assertEq(ERC1155(d).uri(0), "uri://", "module init chain: ERC1155 uri");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC1155Supply() public {
        _expectRecipe(new DeployERC1155Supply().recipeSpec(), 0, "DeployERC1155Supply");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC1155Supply().buildCuts("uri://");
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC1155Supply() public {
        _expectRecipe(new DeployERC1155Supply().recipeSpec(), 1, "DeployERC1155Supply");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC1155Supply().buildCuts("uri://", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(ERC1155(d).uri(0), "uri://", "module init chain: ERC1155 uri");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC1155URIStorage() public {
        _expectRecipe(new DeployERC1155URIStorage().recipeSpec(), 0, "DeployERC1155URIStorage");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC1155URIStorage().buildCuts("uri://", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(ERC1155(d).uri(0), "uri://", "module init chain: ERC1155 uri fallback");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC4626() public {
        _expectRecipe(new DeployERC4626().recipeSpec(), 0, "DeployERC4626");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployERC4626().buildCuts(address(asset), "Vault", "VLT", 0);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC4626() public {
        _expectRecipe(new DeployERC4626().recipeSpec(), 1, "DeployERC4626");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployERC4626().buildCuts(address(asset), "Vault", "VLT", 0, ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(ERC4626(d).asset(), address(asset), "module init: ERC4626 asset");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC1363() public {
        _expectRecipe(new DeployERC1363().recipeSpec(), 0, "DeployERC1363");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC1363().buildCuts("Tok", "TOK");
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC1363() public {
        _expectRecipe(new DeployERC1363().recipeSpec(), 1, "DeployERC1363");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC1363().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(IERC20(d).name(), "Tok", "module init chain: ERC20 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC20TemporaryApproval() public {
        _expectRecipe(new DeployERC20TemporaryApproval().recipeSpec(), 0, "DeployERC20TemporaryApproval");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20TemporaryApproval().buildCuts("Tok", "TOK");
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC20TemporaryApproval() public {
        _expectRecipe(new DeployERC20TemporaryApproval().recipeSpec(), 1, "DeployERC20TemporaryApproval");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20TemporaryApproval().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(IERC20(d).name(), "Tok", "module init chain: ERC20 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC20Burnable() public {
        _expectRecipe(new DeployERC20Burnable().recipeSpec(), 0, "DeployERC20Burnable");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Burnable().buildCuts("Tok", "TOK");
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC20Burnable() public {
        _expectRecipe(new DeployERC20Burnable().recipeSpec(), 1, "DeployERC20Burnable");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Burnable().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(IERC20(d).name(), "Tok", "module init chain: ERC20 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC20Capped() public {
        _expectRecipe(new DeployERC20Capped().recipeSpec(), 0, "DeployERC20Capped");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Capped().buildCuts("Tok", "TOK", 1000 ether);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC20Capped() public {
        _expectRecipe(new DeployERC20Capped().recipeSpec(), 1, "DeployERC20Capped");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Capped().buildCuts("Tok", "TOK", 1000 ether, ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(IERC20(d).name(), "Tok", "module init chain: ERC20 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC20FlashMint() public {
        _expectRecipe(new DeployERC20FlashMint().recipeSpec(), 0, "DeployERC20FlashMint");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20FlashMint().buildCuts("Tok", "TOK");
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC20FlashMint() public {
        _expectRecipe(new DeployERC20FlashMint().recipeSpec(), 1, "DeployERC20FlashMint");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20FlashMint().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(IERC20(d).name(), "Tok", "module init chain: ERC20 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC20Permit() public {
        _expectRecipe(new DeployERC20Permit().recipeSpec(), 0, "DeployERC20Permit");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Permit().buildCuts("Tok", "TOK");
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC20Permit() public {
        _expectRecipe(new DeployERC20Permit().recipeSpec(), 1, "DeployERC20Permit");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Permit().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(IERC20(d).name(), "Tok", "module init chain: ERC20 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC20Wrapper() public {
        _expectRecipe(new DeployERC20Wrapper().recipeSpec(), 0, "DeployERC20Wrapper");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Wrapper().buildCuts("Tok", "TOK", address(asset));
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC20Wrapper() public {
        _expectRecipe(new DeployERC20Wrapper().recipeSpec(), 1, "DeployERC20Wrapper");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Wrapper().buildCuts("Tok", "TOK", address(asset), ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(ERC20Wrapper(d).underlying(), address(asset), "module init: wrapper underlying");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC2981() public {
        _expectRecipe(new DeployERC2981().recipeSpec(), 0, "DeployERC2981");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC2981().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_MarketplaceZone() public {
        _expectRecipe(new DeployMarketplaceZone().recipeSpec(), 0, "DeployMarketplaceZone");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployMarketplaceZone().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC20Pausable() public {
        _expectRecipe(new DeployERC20Pausable().recipeSpec(), 0, "DeployERC20Pausable");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Pausable().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 7);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC20Votes() public {
        _expectRecipe(new DeployERC20Votes().recipeSpec(), 0, "DeployERC20Votes");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Votes().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 7);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC721URIStorage() public {
        _expectRecipe(new DeployERC721URIStorage().recipeSpec(), 0, "DeployERC721URIStorage");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721URIStorage().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC721Burnable() public {
        _expectRecipe(new DeployERC721Burnable().recipeSpec(), 0, "DeployERC721Burnable");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721Burnable().buildCuts("Tok", "TOK");
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC721Burnable() public {
        _expectRecipe(new DeployERC721Burnable().recipeSpec(), 1, "DeployERC721Burnable");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721Burnable().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(ERC721(d).name(), "Tok", "module init chain: ERC721 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC721Consecutive() public {
        (address[] memory receivers, uint96[] memory amounts) = _oneConsecutiveBatch();
        _expectRecipe(new DeployERC721Consecutive().recipeSpec(), 0, "DeployERC721Consecutive");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721Consecutive().buildCuts("Tok", "TOK", 0, receivers, amounts);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 3);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
        assertEq(ERC721(d).balanceOf(ADMIN), 3, "module init chain: batch minted");
    }

    function test_Upgradeable_ERC721Consecutive() public {
        (address[] memory receivers, uint96[] memory amounts) = _oneConsecutiveBatch();
        _expectRecipe(new DeployERC721Consecutive().recipeSpec(), 1, "DeployERC721Consecutive");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721Consecutive().buildCuts("Tok", "TOK", 0, receivers, amounts, ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        assertEq(ERC721(d).ownerOf(2), ADMIN, "module init chain: batch minted");
        _assertAdminCanCut(d, ADMIN);
    }

    function _oneConsecutiveBatch() internal pure returns (address[] memory receivers, uint96[] memory amounts) {
        receivers = new address[](1);
        receivers[0] = ADMIN;
        amounts = new uint96[](1);
        amounts[0] = 3;
    }

    function test_Immutable_ERC721Wrapper() public {
        _expectRecipe(new DeployERC721Wrapper().recipeSpec(), 0, "DeployERC721Wrapper");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721Wrapper().buildCuts("Tok", "TOK", address(asset));
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC721Wrapper() public {
        _expectRecipe(new DeployERC721Wrapper().recipeSpec(), 1, "DeployERC721Wrapper");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721Wrapper().buildCuts("Tok", "TOK", address(asset), ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(ERC721Wrapper(d).underlying(), address(asset), "module init: wrapper underlying");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC721Pausable() public {
        _expectRecipe(new DeployERC721Pausable().recipeSpec(), 0, "DeployERC721Pausable");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721Pausable().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 7);
        _assertBareEth(d, false);
        assertEq(ERC721(d).name(), "Tok", "module init chain: ERC721 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC721Enumerable() public {
        _expectRecipe(new DeployERC721Enumerable().recipeSpec(), 0, "DeployERC721Enumerable");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721Enumerable().buildCuts("Tok", "TOK");
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC721Enumerable() public {
        _expectRecipe(new DeployERC721Enumerable().recipeSpec(), 1, "DeployERC721Enumerable");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721Enumerable().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(ERC721(d).name(), "Tok", "module init chain: ERC721 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC721Votes() public {
        _expectRecipe(new DeployERC721Votes().recipeSpec(), 0, "DeployERC721Votes");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721Votes().buildCuts("Tok", "TOK");
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC721Votes() public {
        _expectRecipe(new DeployERC721Votes().recipeSpec(), 1, "DeployERC721Votes");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721Votes().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 7);
        _assertBareEth(d, false);
        assertEq(ERC721(d).name(), "Tok", "module init chain: ERC721 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC721Royalty() public {
        _expectRecipe(new DeployERC721Royalty().recipeSpec(), 0, "DeployERC721Royalty");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721Royalty().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertEq(ERC721(d).name(), "Tok", "module init chain: ERC721 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC20Crosschain() public {
        _expectRecipe(new DeployERC20Crosschain().recipeSpec(), 0, "DeployERC20Crosschain");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployERC20Crosschain().buildCuts(ADMIN, "Tok", "TOK");
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 7);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC7802() public {
        _expectRecipe(new DeployERC7802().recipeSpec(), 0, "DeployERC7802");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployERC7802().buildCuts(ADMIN, address(this), "Tok", "TOK");
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_HTSAdapter() public {
        _expectRecipe(new DeployHTSAdapter().recipeSpec(), 0, "DeployHTSAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployHTSAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, true);
        _assertAdminCanCut(d, ADMIN);
    }
}
