// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// AUTO-STRUCTURED guard suite — one test per deploy recipe (see RecipeGuards).
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {DeployERC1155} from "@lattice-script/base/tokens/DeployERC1155.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {DeployERC20Burnable} from "@lattice-script/base/tokens/DeployERC20Burnable.s.sol";
import {DeployERC20Capped} from "@lattice-script/base/tokens/DeployERC20Capped.s.sol";
import {DeployERC20Crosschain} from "@lattice-script/base/tokens/DeployERC20Crosschain.s.sol";
import {DeployERC20FlashMint} from "@lattice-script/base/tokens/DeployERC20FlashMint.s.sol";
import {DeployERC20Pausable} from "@lattice-script/base/tokens/DeployERC20Pausable.s.sol";
import {DeployERC20Permit} from "@lattice-script/base/tokens/DeployERC20Permit.s.sol";
import {DeployERC20Votes} from "@lattice-script/base/tokens/DeployERC20Votes.s.sol";
import {DeployERC20Wrapper} from "@lattice-script/base/tokens/DeployERC20Wrapper.s.sol";
import {DeployERC2981} from "@lattice-script/base/tokens/DeployERC2981.s.sol";
import {DeployERC4626} from "@lattice-script/base/tokens/DeployERC4626.s.sol";
import {DeployERC721} from "@lattice-script/base/tokens/DeployERC721.s.sol";
import {DeployERC721URIStorage} from "@lattice-script/base/tokens/DeployERC721URIStorage.s.sol";
import {DeployERC7802} from "@lattice-script/base/tokens/DeployERC7802.s.sol";
import {DeployMarketplaceZone} from "@lattice-script/base/tokens/DeployMarketplaceZone.s.sol";
import {RecipeGuards} from "@lattice-test/composability/RecipeGuards.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ERC1155} from "@lattice/tokens/ERC1155/ERC1155.sol";
import {ERC20Wrapper} from "@lattice/tokens/ERC20/ERC20Wrapper.sol";
import {ERC4626} from "@lattice/tokens/ERC4626/ERC4626.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";

/// @title RecipeUpgradeabilityTokensTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Tokens-family recipe guards: every diamond these recipes assemble must be introspectable and
///         either admin-upgradeable or immutable BY DESIGN (never silently frozen).
contract RecipeUpgradeabilityTokensTest is RecipeGuards {
    TestnetAsset internal asset;

    function setUp() public {
        asset = new TestnetAsset("Guard Asset", "GA");
    }

    function test_Immutable_ERC20() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC20().buildCuts("Tok", "TOK");
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC20() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC20().buildCuts("Tok", "TOK", ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        assertEq(IERC20(d).name(), "Tok", "module init: ERC20 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC721() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC721().buildCuts("Tok", "TOK");
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC721() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC721().buildCuts("Tok", "TOK", ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        assertEq(ERC721(d).name(), "Tok", "module init: ERC721 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC1155() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC1155().buildCuts("uri://");
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC1155() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC1155().buildCuts("uri://", ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        assertEq(ERC1155(d).uri(0), "uri://", "module init: ERC1155 uri");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC4626() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployERC4626().buildCuts(address(asset), "Vault", "VLT", 0);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 4);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC4626() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployERC4626().buildCuts(address(asset), "Vault", "VLT", 0, ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        assertEq(ERC4626(d).asset(), address(asset), "module init: ERC4626 asset");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC20Burnable() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Burnable().buildCuts("Tok", "TOK");
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC20Burnable() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Burnable().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        assertEq(IERC20(d).name(), "Tok", "module init chain: ERC20 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC20Capped() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Capped().buildCuts("Tok", "TOK", 1000 ether);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC20Capped() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Capped().buildCuts("Tok", "TOK", 1000 ether, ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        assertEq(IERC20(d).name(), "Tok", "module init chain: ERC20 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC20FlashMint() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20FlashMint().buildCuts("Tok", "TOK");
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC20FlashMint() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20FlashMint().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        assertEq(IERC20(d).name(), "Tok", "module init chain: ERC20 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC20Permit() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Permit().buildCuts("Tok", "TOK");
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC20Permit() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Permit().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        assertEq(IERC20(d).name(), "Tok", "module init chain: ERC20 name");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC20Wrapper() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Wrapper().buildCuts("Tok", "TOK", address(asset));
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 4);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC20Wrapper() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Wrapper().buildCuts("Tok", "TOK", address(asset), ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        assertEq(ERC20Wrapper(d).underlying(), address(asset), "module init: wrapper underlying");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC2981() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC2981().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_MarketplaceZone() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployMarketplaceZone().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC20Pausable() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Pausable().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 7);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC20Votes() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC20Votes().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 7);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC721URIStorage() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory cds) =
            new DeployERC721URIStorage().buildCuts("Tok", "TOK", ADMIN);
        address d = _assembleMulti(cuts, inits, cds);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC20Crosschain() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployERC20Crosschain().buildCuts(ADMIN, "Tok", "TOK");
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 7);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ERC7802() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployERC7802().buildCuts(ADMIN, address(this), "Tok", "TOK");
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }
}
