// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Burnable} from "@lattice/interfaces/tokens/IERC20Burnable.sol";
import {ERC20Burnable} from "@lattice/tokens/ERC20/ERC20Burnable.sol";
import {ERC20BurnableLib} from "@lattice/tokens/ERC20/libraries/ERC20BurnableLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockERC20BurnableContract
contract MockERC20BurnableContract is ERC20Burnable {
    function initialize(string memory name_, string memory symbol_, address mintTo, uint256 mintAmount) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init(name_, symbol_);
        ERC20BurnableLib.__ERC20Burnable_init();
        if (mintTo != address(0) && mintAmount > 0) {
            ERC20Lib._mint(mintTo, mintAmount);
        }
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC20BurnableTester
contract ERC20BurnableTester is Test {
    MockERC20BurnableContract token;

    address alice = address(0x1);
    address bob = address(0x2);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new MockERC20BurnableContract();
        token.initialize("Burn Token", "BURN", alice, INITIAL_SUPPLY);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               BURN TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_BurnReducesTotalSupplyAndCallerBalance() public {
        uint256 burnAmount = 100e18;
        uint256 supplyBefore = token.totalSupply();
        uint256 balanceBefore = token.balanceOf(alice);

        vm.prank(alice);
        token.burn(burnAmount);

        assertEq(token.totalSupply(), supplyBefore - burnAmount);
        assertEq(token.balanceOf(alice), balanceBefore - burnAmount);
    }

    function test_BurnEmitsTransferToZero() public {
        uint256 burnAmount = 50e18;
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, address(0), burnAmount);
        vm.prank(alice);
        token.burn(burnAmount);
    }

    function test_BurnMoreThanBalanceReverts() public {
        uint256 tooMuch = INITIAL_SUPPLY + 1;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20.ERC20InsufficientBalance.selector, alice, INITIAL_SUPPLY, tooMuch)
        );
        token.burn(tooMuch);
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
        token.burnFrom(alice, burnAmount);

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
        token.burnFrom(alice, tooBig);
    }

    function test_BurnFromEmitsTransferToZero() public {
        uint256 burnAmount = 75e18;

        vm.prank(alice);
        token.approve(bob, burnAmount);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, address(0), burnAmount);

        vm.prank(bob);
        token.burnFrom(alice, burnAmount);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIERC20Burnable() public view {
        assertTrue(token.supportsInterface(type(IERC20Burnable).interfaceId));
    }

    function test_SupportsIERC20() public view {
        assertTrue(token.supportsInterface(type(IERC20).interfaceId));
    }
}
