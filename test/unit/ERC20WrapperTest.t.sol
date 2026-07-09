// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20Wrapper} from "@lattice-script/base/tokens/DeployERC20Wrapper.s.sol";
import {ERC20TestBase} from "@lattice-test/base/ERC20TestBase.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Wrapper} from "@lattice/interfaces/tokens/IERC20Wrapper.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Wrapper} from "@lattice/tokens/ERC20/ERC20Wrapper.sol";

/// @title ERC20WrapperTest
/// @notice Exercises the {ERC20Wrapper} facet (1:1 wrapping of an underlying ERC-20) through a REAL {Diamond}
///         assembled by the ready-to-deploy {DeployERC20Wrapper} script. The underlying is itself a REAL base
///         ERC-20 diamond (via {DeployERC20}); the wrapper facet is a MIXED cut whose `decimals()` REPLACES the
///         base and whose `underlying`/`depositFor`/`withdrawTo` are ADDED. `recover()` is access-controlled on the
///         production facet, so it is driven through the test-only {TokenTestFacet} (`helper`). Every call routes
///         through the diamond's `delegatecall` dispatch, not a flattened inheritance mock.
contract ERC20WrapperTest is ERC20TestBase {
    ERC20Wrapper internal wrapper;

    address internal underlyingAddr;
    ERC20 internal underlyingToken;
    TokenTestFacet internal underlyingHelper;

    address alice = address(0x1);
    address bob = address(0x2);
    uint256 constant START = 1000e6;
    uint256 constant AMT = 250e6;

    function setUp() public override {
        // Underlying: a real base ERC-20 diamond, seeded with a balance for alice via the test helper facet.
        underlyingAddr = _deployERC20("Underlying", "UND", new FacetCut[](0));
        underlyingToken = ERC20(underlyingAddr);
        underlyingHelper = TokenTestFacet(underlyingAddr);
        underlyingHelper.mint(alice, START);

        // Wrapper: a real diamond wrapping the underlying 1:1.
        DeployERC20Wrapper d = new DeployERC20Wrapper();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            d.buildCuts("Wrapped Underlying", "wUND", underlyingAddr);
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC20(diamond);
        helper = TokenTestFacet(diamond);
        wrapper = ERC20Wrapper(diamond);

        vm.prank(alice);
        underlyingToken.approve(diamond, type(uint256).max);
    }

    function test_UnderlyingAndMirroredDecimals() public view {
        assertEq(wrapper.underlying(), underlyingAddr, "underlying recorded");
        assertEq(wrapper.decimals(), underlyingToken.decimals(), "decimals mirror underlying");
    }

    function test_SupportsWrapperInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20Wrapper).interfaceId), "registers IERC20Wrapper");
    }

    function test_DepositForPullsUnderlyingAndMintsWrapped() public {
        vm.prank(alice);
        bool ok = wrapper.depositFor(bob, AMT);
        assertTrue(ok);
        assertEq(underlyingToken.balanceOf(diamond), AMT, "underlying escrowed");
        assertEq(underlyingToken.balanceOf(alice), START - AMT, "underlying debited from caller");
        assertEq(token.balanceOf(bob), AMT, "wrapped minted to account");
        assertEq(token.totalSupply(), AMT, "wrapped supply tracks deposit");
    }

    function test_WithdrawToBurnsWrappedAndReturnsUnderlying() public {
        vm.prank(alice);
        wrapper.depositFor(alice, AMT);
        vm.prank(alice);
        bool ok = wrapper.withdrawTo(bob, AMT);
        assertTrue(ok);
        assertEq(token.balanceOf(alice), 0, "wrapped burned");
        assertEq(token.totalSupply(), 0, "supply back to zero");
        assertEq(underlyingToken.balanceOf(bob), AMT, "underlying released to account");
    }

    function test_DepositRevertsForSelfReceiver() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidReceiver.selector, diamond));
        wrapper.depositFor(diamond, AMT);
    }

    function test_WithdrawRevertsForSelfReceiver() public {
        vm.prank(alice);
        wrapper.depositFor(alice, AMT);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidReceiver.selector, diamond));
        wrapper.withdrawTo(diamond, AMT);
    }

    function test_RecoverMintsSurplus() public {
        // tokens sent directly to the wrapper (not via depositFor) leave supply < underlying balance
        underlyingHelper.mint(diamond, AMT);
        uint256 recovered = helper.recover(bob);
        assertEq(recovered, AMT, "surplus recovered");
        assertEq(token.balanceOf(bob), AMT, "wrapped minted for surplus");
    }

    function test_InitRevertsWhenUnderlyingIsSelf() public {
        // Pre-deploy the diamond so its address is known, then init the wrapper with itself as the underlying.
        Diamond d = new Diamond();
        DeployERC20Wrapper dep = new DeployERC20Wrapper();
        (FacetCut[] memory prodCuts, address[] memory inits, bytes[] memory initCalldatas) =
            dep.buildCuts("Wrapped Underlying", "wUND", address(d));

        FacetCut[] memory cuts = new FacetCut[](prodCuts.length + 1);
        for (uint256 i; i < prodCuts.length; ++i) {
            cuts[i] = prodCuts[i];
        }
        cuts[prodCuts.length] = _helperCut();

        MultiInit mi = new MultiInit();
        vm.expectRevert(abi.encodeWithSelector(IERC20Wrapper.ERC20InvalidUnderlying.selector, address(d)));
        d.initialize(cuts, address(mi), abi.encodeCall(MultiInit.multiInit, (inits, initCalldatas)));
    }
}
