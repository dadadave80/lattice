// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20Burnable} from "@lattice-script/base/tokens/DeployERC20Burnable.s.sol";
import {ERC20TestBase} from "@lattice-test/base/ERC20TestBase.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Burnable} from "@lattice/interfaces/tokens/IERC20Burnable.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";

/// @title ERC20BurnableTest
/// @notice Exercises the {ERC20Burnable} facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployERC20Burnable} script (base ERC-20 + the additive burnable facet). Every call routes through the
///         diamond's `delegatecall` dispatch, not a flattened inheritance mock; `mint` comes from the test-only
///         {TokenTestFacet} (`helper`) and `supportsInterface` from the cut-in `ERC165Facet`.
contract ERC20BurnableTest is ERC20TestBase {
    IERC20Burnable internal burnable;

    address alice = address(0x1);
    address bob = address(0x2);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public override {
        DeployERC20Burnable d = new DeployERC20Burnable();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            d.buildCuts("Burn Token", "BURN");
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC20(diamond);
        helper = TokenTestFacet(diamond);
        burnable = IERC20Burnable(diamond);

        helper.mint(alice, INITIAL_SUPPLY);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               BURN TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_BurnReducesTotalSupplyAndCallerBalance() public {
        uint256 burnAmount = 100e18;
        uint256 supplyBefore = token.totalSupply();
        uint256 balanceBefore = token.balanceOf(alice);

        vm.prank(alice);
        burnable.burn(burnAmount);

        assertEq(token.totalSupply(), supplyBefore - burnAmount);
        assertEq(token.balanceOf(alice), balanceBefore - burnAmount);
    }

    function test_BurnEmitsTransferToZero() public {
        uint256 burnAmount = 50e18;
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, address(0), burnAmount);
        vm.prank(alice);
        burnable.burn(burnAmount);
    }

    function test_BurnMoreThanBalanceReverts() public {
        uint256 tooMuch = INITIAL_SUPPLY + 1;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20.ERC20InsufficientBalance.selector, alice, INITIAL_SUPPLY, tooMuch)
        );
        burnable.burn(tooMuch);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             BURNFROM TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_BurnFromUsesAllowance() public {
        uint256 approved = 200e18;
        uint256 burnAmount = 100e18;
        uint256 supplyBefore = token.totalSupply();

        vm.prank(alice);
        token.approve(bob, approved);

        vm.prank(bob);
        burnable.burnFrom(alice, burnAmount);

        assertEq(token.totalSupply(), supplyBefore - burnAmount);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - burnAmount);
        assertEq(token.allowance(alice, bob), approved - burnAmount);
    }

    function test_BurnFromInsufficientAllowanceReverts() public {
        uint256 approved = 50e18;
        uint256 tooBig = 100e18;

        vm.prank(alice);
        token.approve(bob, approved);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InsufficientAllowance.selector, bob, approved, tooBig));
        burnable.burnFrom(alice, tooBig);
    }

    function test_BurnFromEmitsTransferToZero() public {
        uint256 burnAmount = 75e18;

        vm.prank(alice);
        token.approve(bob, burnAmount);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, address(0), burnAmount);

        vm.prank(bob);
        burnable.burnFrom(alice, burnAmount);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIERC20Burnable() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20Burnable).interfaceId));
    }

    function test_SupportsIERC20() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20).interfaceId));
    }
}
