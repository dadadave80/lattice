// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20Capped} from "@lattice-script/base/tokens/DeployERC20Capped.s.sol";
import {ERC20TestBase} from "@lattice-test/base/ERC20TestBase.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Capped} from "@lattice/interfaces/tokens/IERC20Capped.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Capped} from "@lattice/tokens/ERC20/ERC20Capped.sol";

/// @title ERC20CappedTest
/// @notice Exercises the {ERC20Capped} facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployERC20Capped} script (base ERC-20 + the additive capped facet + a cap-seeding init). Every call
///         routes through the diamond's `delegatecall` dispatch, not a flattened inheritance mock. The production
///         {ERC20Capped} facet keeps minting internal (app-specific), so cap-enforced minting is driven through the
///         test-only {TokenTestFacet.cappedMint} — which runs the SAME {ERC20CappedLib._checkCap} guard the facet's
///         `_mint` uses — and `supportsInterface` comes from the cut-in `ERC165Facet`.
contract ERC20CappedTest is ERC20TestBase {
    ERC20Capped internal capped;

    address alice = address(0x3);

    uint256 constant CAP = 1_000_000e18;

    function setUp() public override {
        DeployERC20Capped d = new DeployERC20Capped();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            d.buildCuts("Capped Token", "CAP", CAP);
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC20(diamond);
        helper = TokenTestFacet(diamond);
        capped = ERC20Capped(diamond);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               CAP QUERY
    //////////////////////////////////////////////////////////////////////////*//

    function test_CapIsQueryable() public view {
        assertEq(capped.cap(), CAP);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            MINT UP TO CAP
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintUpToCapSucceeds() public {
        helper.cappedMint(alice, CAP);
        assertEq(token.totalSupply(), CAP);
        assertEq(token.balanceOf(alice), CAP);
    }

    function test_MintBelowCapSucceeds() public {
        helper.cappedMint(alice, CAP / 2);
        assertEq(token.totalSupply(), CAP / 2);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           MINT BEYOND CAP
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintBeyondCapReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Capped.ERC20ExceededCap.selector, CAP + 1, CAP));
        helper.cappedMint(alice, CAP + 1);
    }

    function test_MintBeyondCapAfterPartialMintReverts() public {
        helper.cappedMint(alice, CAP - 10e18);

        uint256 remaining = capped.cap() - token.totalSupply();
        uint256 overMint = remaining + 1;
        uint256 newSupply = token.totalSupply() + overMint;

        vm.expectRevert(abi.encodeWithSelector(IERC20Capped.ERC20ExceededCap.selector, newSupply, CAP));
        helper.cappedMint(alice, overMint);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //         MIN-02: boundary — minting exactly to cap in two steps succeeds
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintExactlyToCapInTwoStepsSucceeds() public {
        uint256 firstMint = CAP / 2;
        uint256 secondMint = CAP - firstMint; // CAP - CAP/2 handles odd CAP values

        helper.cappedMint(alice, firstMint);
        helper.cappedMint(alice, secondMint);

        // totalSupply == cap (check is >, not >=, so this must not revert)
        assertEq(token.totalSupply(), CAP);
        assertEq(token.totalSupply(), capped.cap());
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          INVALID CAP ON INIT
    //////////////////////////////////////////////////////////////////////////*//

    function test_ZeroCapInInitReverts() public {
        // Pre-deploy the diamond so `expectRevert` can target the initialize call directly.
        Lattice d = new Lattice();
        DeployERC20Capped dep = new DeployERC20Capped();
        (FacetCut[] memory prodCuts, address[] memory inits, bytes[] memory initCalldatas) =
            dep.buildCuts("Bad Cap Token", "BAD", 0);

        FacetCut[] memory cuts = new FacetCut[](prodCuts.length + 1);
        for (uint256 i; i < prodCuts.length; ++i) {
            cuts[i] = prodCuts[i];
        }
        cuts[prodCuts.length] = _helperCut();

        MultiInit mi = new MultiInit();
        vm.expectRevert(abi.encodeWithSelector(IERC20Capped.ERC20InvalidCap.selector, 0));
        d.initialize(cuts, address(mi), abi.encodeCall(MultiInit.multiInit, (inits, initCalldatas)));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIERC20Capped() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20Capped).interfaceId));
    }

    function test_SupportsIERC20() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20).interfaceId));
    }
}
