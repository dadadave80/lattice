// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal mock ERC20 for gas tests.
contract GasERC20 is ERC20 {
    function initialize(string memory name_, string memory symbol_, address mintTo, uint256 mintAmount) external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init(name_, symbol_);
        if (mintTo != address(0) && mintAmount > 0) {
            ERC20Lib._mint(mintTo, mintAmount);
        }
        InitializableLib.postInitializer(s);
    }

    function mint(address to, uint256 value) external {
        ERC20Lib._mint(to, value);
    }
}

/// @title ERC20GasTest
/// @notice Gas snapshot tests for hot paths in the ERC20 module.
contract ERC20GasTest is Test {
    GasERC20 token;

    address alice = address(0x1);
    address bob = address(0x2);
    address spender = address(0x3);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 constant TRANSFER_AMOUNT = 100e18;

    // Generous upper bounds (roughly 3× expected) so the suite does not flicker.
    uint256 constant GAS_BOUND_TRANSFER = 60_000;
    uint256 constant GAS_BOUND_APPROVE = 60_000;
    uint256 constant GAS_BOUND_TRANSFER_FROM = 60_000;
    uint256 constant GAS_BOUND_MINT = 60_000;

    function setUp() public {
        token = new GasERC20();
        token.initialize("Gas Token", "GAS", alice, INITIAL_SUPPLY);
    }

    /// @notice Gas cost of a standard ERC20 transfer between two EOAs.
    function test_Gas_Transfer() public {
        vm.prank(alice);
        vm.startSnapshotGas("ERC20.transfer");
        token.transfer(bob, TRANSFER_AMOUNT);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertLt(gasUsed, GAS_BOUND_TRANSFER, "ERC20.transfer gas regression");
    }

    /// @notice Gas cost of approve followed by transferFrom.
    function test_Gas_ApproveAndTransferFrom() public {
        // Snapshot approve
        vm.prank(alice);
        vm.startSnapshotGas("ERC20.approve");
        token.approve(spender, TRANSFER_AMOUNT);
        uint256 approveGas = vm.stopSnapshotGas();
        assertLt(approveGas, GAS_BOUND_APPROVE, "ERC20.approve gas regression");

        // Snapshot transferFrom
        vm.prank(spender);
        vm.startSnapshotGas("ERC20.transferFrom");
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);
        uint256 transferFromGas = vm.stopSnapshotGas();
        assertLt(transferFromGas, GAS_BOUND_TRANSFER_FROM, "ERC20.transferFrom gas regression");
    }

    /// @notice Gas cost of minting tokens via the admin helper.
    function test_Gas_MintByAdmin() public {
        vm.startSnapshotGas("ERC20.mint");
        token.mint(bob, TRANSFER_AMOUNT);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertLt(gasUsed, GAS_BOUND_MINT, "ERC20.mint gas regression");
    }
}
