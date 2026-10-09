// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal mock ERC20 for gas tests.
contract GasERC20 is ERC20, Initializable {
    function initialize(string memory name_, string memory symbol_, address mintTo, uint256 mintAmount)
        external
        initializer
    {
        ERC20Lib.__ERC20_init(name_, symbol_);
        if (mintTo != address(0) && mintAmount > 0) {
            ERC20Lib._mint(mintTo, mintAmount);
        }
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

    function setUp() public {
        token = new GasERC20();
        token.initialize("Gas Token", "GAS", alice, INITIAL_SUPPLY);
    }

    /// @notice Gas cost of a standard ERC20 transfer between two EOAs.
    function test_Gas_Transfer() public {
        vm.prank(alice);
        vm.startSnapshotGas("ERC20.transfer");
        token.transfer(bob, TRANSFER_AMOUNT);
        vm.stopSnapshotGas();
    }

    /// @notice Gas cost of approve followed by transferFrom.
    function test_Gas_ApproveAndTransferFrom() public {
        // Snapshot approve
        vm.prank(alice);
        vm.startSnapshotGas("ERC20.approve");
        token.approve(spender, TRANSFER_AMOUNT);
        vm.stopSnapshotGas();

        // Snapshot transferFrom
        vm.prank(spender);
        vm.startSnapshotGas("ERC20.transferFrom");
        token.transferFrom(alice, bob, TRANSFER_AMOUNT);
        vm.stopSnapshotGas();
    }

    /// @notice Gas cost of minting tokens via the admin helper.
    function test_Gas_MintByAdmin() public {
        vm.startSnapshotGas("ERC20.mint");
        token.mint(bob, TRANSFER_AMOUNT);
        vm.stopSnapshotGas();
    }
}
