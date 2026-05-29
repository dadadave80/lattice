// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {ERC20} from "@lattice/tokens/ERC20.sol";
import {ERC20Lib} from "@lattice/tokens/libraries/ERC20Lib.sol";
import {IERC20} from "@lattice/interfaces/IERC20.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockERC20Contract
/// @notice Mock ERC-20 token for testing, with mint access for tests.
contract MockERC20Contract is ERC20 {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function initialize(string memory name_, string memory symbol_, address mintTo, uint256 mintAmount) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init(name_, symbol_);
        if (mintTo != address(0) && mintAmount > 0) {
            ERC20Lib._mint(mintTo, mintAmount);
        }
        InitializableLib.postInitializer(s);
    }

    /// @notice Expose internal _mint for tests.
    function mint(address to, uint256 value) external {
        ERC20Lib._mint(to, value);
    }

    /// @notice Expose internal _burn for tests.
    function burn(address from, uint256 value) external {
        ERC20Lib._burn(from, value);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC20Tester
contract ERC20Tester is Test {
    MockERC20Contract token;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new MockERC20Contract();
        token.initialize("Test Token", "TEST", alice, INITIAL_SUPPLY);
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
        // Direct call to internal path via mock's burn (which calls _update(from, address(0)))
        // We test InvalidSender by calling mint to zero (which internally calls _update(address(0), to))
        // For InvalidSender on _transfer, we use the public transfer which requires from == msgSender.
        // Instead test via the internal _burn path exposed by mock.
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidSender.selector, address(0)));
        token.burn(address(0), 1);
    }

    function test_TransferInsufficientBalanceReverts() public {
        uint256 tooMuch = INITIAL_SUPPLY + 1;
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InsufficientBalance.selector, alice, INITIAL_SUPPLY, tooMuch));
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
        assertTrue(token.supportsInterface(type(IERC20).interfaceId));
    }

    function test_DoesNotSupportRandomInterface() public view {
        assertFalse(token.supportsInterface(bytes4(0xdeadbeef)));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          MINT / BURN VIA MOCK
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintIncreasesTotalSupply() public {
        uint256 before = token.totalSupply();
        token.mint(bob, 1e18);
        assertEq(token.totalSupply(), before + 1e18);
        assertEq(token.balanceOf(bob), 1e18);
    }

    function test_BurnDecreasesTotalSupply() public {
        uint256 before = token.totalSupply();
        vm.prank(alice);
        token.burn(alice, 1e18);
        assertEq(token.totalSupply(), before - 1e18);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - 1e18);
    }

    function test_MintToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InvalidReceiver.selector, address(0)));
        token.mint(address(0), 1e18);
    }
}
