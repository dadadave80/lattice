// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ERC20TestBase} from "@lattice-test/base/ERC20TestBase.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @title ERC20Test
/// @notice Exercises the base ERC-20 facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployERC20} script (see {ERC20TestBase}) — every call below routes through the diamond's
///         `delegatecall` dispatch, not a flattened inheritance mock. `mint`/`burn` come from the test-only
///         {TokenTestFacet} (`helper`); `supportsInterface` from the cut-in `ERC165Facet`.
contract ERC20Test is ERC20TestBase {
    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public override {
        super.setUp(); // deploys the ERC-20 diamond ("Test Token"/"TEST") and wires `token`/`helper`
        helper.mint(alice, INITIAL_SUPPLY);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               METADATA TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_Name() public view {
        assertEq(token.name(), "Test Token");
    }

    function test_Symbol() public view {
        assertEq(token.symbol(), "TEST");
    }

    function test_Decimals() public view {
        assertEq(token.decimals(), 18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIAL STATE
    //////////////////////////////////////////////////////////////////////////*//

    function test_TotalSupply() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function test_BalanceAfterMint() public view {
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY);
    }

    function test_BalanceOfUnknownAddressIsZero() public view {
        assertEq(token.balanceOf(bob), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              TRANSFER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_TransferHappyPath() public {
        uint256 amount = 100e18;
        vm.prank(alice);
        bool ok = token.transfer(bob, amount);
        assertTrue(ok);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - amount);
        assertEq(token.balanceOf(bob), amount);
    }

    function test_TransferEmitsEvent() public {
        uint256 amount = 50e18;
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, amount);
        vm.prank(alice);
        token.transfer(bob, amount);
    }

    function test_TransferToZeroAddressReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    function test_TransferFromZeroAddressReverts() public {
        // _burn(address(0), ..) hits the ERC20InvalidSender path of _update (exposed via the test helper facet).
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidSender.selector, address(0)));
        helper.burn(address(0), 1);
    }

    function test_TransferInsufficientBalanceReverts() public {
        uint256 tooMuch = INITIAL_SUPPLY + 1;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20.ERC20InsufficientBalance.selector, alice, INITIAL_SUPPLY, tooMuch)
        );
        token.transfer(bob, tooMuch);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               APPROVE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ApproveAndAllowance() public {
        uint256 amount = 500e18;
        vm.prank(alice);
        bool ok = token.approve(bob, amount);
        assertTrue(ok);
        assertEq(token.allowance(alice, bob), amount);
    }

    function test_ApproveEmitsEvent() public {
        uint256 amount = 200e18;
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(alice, bob, amount);
        vm.prank(alice);
        token.approve(bob, amount);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            TRANSFERFROM TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_TransferFromUsesAllowance() public {
        uint256 approved = 300e18;
        uint256 spent = 100e18;

        vm.prank(alice);
        token.approve(bob, approved);

        vm.prank(bob);
        bool ok = token.transferFrom(alice, charlie, spent);
        assertTrue(ok);

        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - spent);
        assertEq(token.balanceOf(charlie), spent);
        assertEq(token.allowance(alice, bob), approved - spent);
    }

    function test_TransferFromWithMaxAllowanceDoesNotDecrement() public {
        uint256 maxAllowance = type(uint256).max;

        vm.prank(alice);
        token.approve(bob, maxAllowance);

        vm.prank(bob);
        token.transferFrom(alice, charlie, 100e18);

        assertEq(token.allowance(alice, bob), maxAllowance, "max allowance should not be decremented");
    }

    function test_TransferFromInsufficientAllowanceReverts() public {
        uint256 approved = 50e18;
        uint256 toSpend = 100e18;

        vm.prank(alice);
        token.approve(bob, approved);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InsufficientAllowance.selector, bob, approved, toSpend));
        token.transferFrom(alice, charlie, toSpend);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIERC20() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20).interfaceId));
    }

    function test_DoesNotSupportRandomInterface() public view {
        assertFalse(ERC165Facet(diamond).supportsInterface(bytes4(0xdeadbeef)));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          MINT / BURN VIA TEST FACET
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintIncreasesTotalSupply() public {
        uint256 before = token.totalSupply();
        helper.mint(bob, 1e18);
        assertEq(token.totalSupply(), before + 1e18);
        assertEq(token.balanceOf(bob), 1e18);
    }

    function test_BurnDecreasesTotalSupply() public {
        uint256 before = token.totalSupply();
        helper.burn(alice, 1e18);
        assertEq(token.totalSupply(), before - 1e18);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - 1e18);
    }

    function test_MintToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidReceiver.selector, address(0)));
        helper.mint(address(0), 1e18);
    }
}
