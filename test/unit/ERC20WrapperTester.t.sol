// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Wrapper} from "@lattice/interfaces/tokens/IERC20Wrapper.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Wrapper} from "@lattice/tokens/ERC20/ERC20Wrapper.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC20WrapperLib} from "@lattice/tokens/ERC20/libraries/ERC20WrapperLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice A plain ERC-20 underlying with 6 decimals, used to verify the wrapper mirrors decimals.
contract MockUnderlying is ERC20 {
    function initialize(address mintTo, uint256 amount) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init("Underlying", "UND");
        ERC20Lib._mint(mintTo, amount);
        InitializableLib.postInitializer(s);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        ERC20Lib._mint(to, amount);
    }
}

contract MockWrapperContract is ERC20Wrapper {
    function initialize(address underlying_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init("Wrapped Underlying", "wUND");
        ERC20WrapperLib.__ERC20Wrapper_init(underlying_);
        InitializableLib.postInitializer(s);
    }

    /// @dev Test-only exposure of the access-controlled recover().
    function recover(address account) external returns (uint256) {
        return ERC20WrapperLib.recover(account);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC20WrapperTester
/// @notice ERC20 batch (token-extension completion): 1:1 wrapping of an underlying ERC-20.
contract ERC20WrapperTester is Test {
    MockUnderlying underlying;
    MockWrapperContract wrapper;

    address alice = address(0x1);
    address bob = address(0x2);
    uint256 constant START = 1000e6;
    uint256 constant AMT = 250e6;

    function setUp() public {
        underlying = new MockUnderlying();
        underlying.initialize(alice, START);
        wrapper = new MockWrapperContract();
        wrapper.initialize(address(underlying));
        vm.prank(alice);
        underlying.approve(address(wrapper), type(uint256).max);
    }

    function test_UnderlyingAndMirroredDecimals() public view {
        assertEq(wrapper.underlying(), address(underlying), "underlying recorded");
        assertEq(wrapper.decimals(), 6, "decimals mirror underlying");
    }

    function test_SupportsWrapperInterface() public view {
        assertTrue(wrapper.supportsInterface(type(IERC20Wrapper).interfaceId), "registers IERC20Wrapper");
    }

    function test_DepositForPullsUnderlyingAndMintsWrapped() public {
        vm.prank(alice);
        bool ok = wrapper.depositFor(bob, AMT);
        assertTrue(ok);
        assertEq(underlying.balanceOf(address(wrapper)), AMT, "underlying escrowed");
        assertEq(underlying.balanceOf(alice), START - AMT, "underlying debited from caller");
        assertEq(wrapper.balanceOf(bob), AMT, "wrapped minted to account");
        assertEq(wrapper.totalSupply(), AMT, "wrapped supply tracks deposit");
    }

    function test_WithdrawToBurnsWrappedAndReturnsUnderlying() public {
        vm.prank(alice);
        wrapper.depositFor(alice, AMT);
        vm.prank(alice);
        bool ok = wrapper.withdrawTo(bob, AMT);
        assertTrue(ok);
        assertEq(wrapper.balanceOf(alice), 0, "wrapped burned");
        assertEq(wrapper.totalSupply(), 0, "supply back to zero");
        assertEq(underlying.balanceOf(bob), AMT, "underlying released to account");
    }

    function test_DepositRevertsForSelfReceiver() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidReceiver.selector, address(wrapper)));
        wrapper.depositFor(address(wrapper), AMT);
    }

    function test_WithdrawRevertsForSelfReceiver() public {
        vm.prank(alice);
        wrapper.depositFor(alice, AMT);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidReceiver.selector, address(wrapper)));
        wrapper.withdrawTo(address(wrapper), AMT);
    }

    function test_RecoverMintsSurplus() public {
        // tokens sent directly to the wrapper (not via depositFor) leave supply < underlying balance
        underlying.mint(address(wrapper), AMT);
        uint256 recovered = wrapper.recover(bob);
        assertEq(recovered, AMT, "surplus recovered");
        assertEq(wrapper.balanceOf(bob), AMT, "wrapped minted for surplus");
    }

    function test_InitRevertsWhenUnderlyingIsSelf() public {
        MockWrapperContract w = new MockWrapperContract();
        vm.expectRevert(abi.encodeWithSelector(IERC20Wrapper.ERC20InvalidUnderlying.selector, address(w)));
        w.initialize(address(w));
    }
}
