// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Votes} from "@lattice/tokens/ERC20/ERC20Votes.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC20VotesLib} from "@lattice/tokens/ERC20/libraries/ERC20VotesLib.sol";
import {ERC4626} from "@lattice/tokens/ERC4626/ERC4626.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Mintable ERC20Votes token used as the vault's underlying asset.
contract GasERC20Votes is ERC20, ERC20Votes {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(ERC20, ERC20Votes) returns (bytes memory) {}

    function transfer(address to, uint256 value) public override(ERC20, ERC20Votes) returns (bool) {
        return ERC20Votes.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override(ERC20, ERC20Votes) returns (bool) {
        return ERC20Votes.transferFrom(from, to, value);
    }

    function initialize(string memory name_, string memory symbol_, address admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init(name_, symbol_);
        EIP712Lib.__EIP712_init(name_, "1");
        NoncesLib.__Nonces_init();
        VotesLib.__Votes_init();
        ERC20VotesLib.__ERC20Votes_init();
        AccessControlLib.__AccessControl_init(admin);
        InitializableLib.postInitializer(s);
    }

    function mint(address to, uint256 value) external {
        ERC20VotesLib._mint(to, value);
    }
}

/// @notice Mock ERC4626 vault for gas tests.
contract GasVault is ERC4626 {
    function initialize(address asset_, string memory name_, string memory symbol_, uint8 decimalsOffset_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init(name_, symbol_);
        ERC4626Lib.__ERC4626_init(asset_, decimalsOffset_);
        AccessControlLib.__AccessControl_init(msg.sender);
        InitializableLib.postInitializer(s);
    }
}

/// @title ERC4626GasTest
/// @notice Gas snapshot tests for hot paths in the ERC4626 vault module.
contract ERC4626GasTest is Test {
    GasVault vault;
    GasERC20Votes underlying;

    address admin = address(0xAD);
    address alice = address(0xA1);
    address bob = address(0xB0B);

    uint256 constant INITIAL_MINT = 1_000e18;
    uint256 constant DEPOSIT_AMOUNT = 100e18;

    // Generous upper bounds (~3× expected).
    uint256 constant GAS_BOUND_DEPOSIT = 250_000;
    uint256 constant GAS_BOUND_WITHDRAW = 150_000;
    uint256 constant GAS_BOUND_REDEEM = 150_000;

    function setUp() public {
        underlying = new GasERC20Votes();
        underlying.initialize("Gas Token", "GAS", admin);

        underlying.mint(alice, INITIAL_MINT);
        underlying.mint(bob, INITIAL_MINT);

        vault = new GasVault();
        vault.initialize(address(underlying), "Gas Vault", "gGAS", 0);
    }

    /// @notice Gas cost of a deposit when totalSupply == 0 (first depositor, no shares yet).
    function test_Gas_Deposit() public {
        vm.prank(alice);
        underlying.approve(address(vault), DEPOSIT_AMOUNT);

        vm.prank(alice);
        vm.startSnapshotGas("ERC4626.deposit.first");
        vault.deposit(DEPOSIT_AMOUNT, alice);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertLt(gasUsed, GAS_BOUND_DEPOSIT, "ERC4626.deposit.first gas regression");
    }

    /// @notice Gas cost of a deposit when totalSupply > 0 (subsequent depositor, share price math active).
    function test_Gas_DepositSubsequent() public {
        // Seed the vault with alice's deposit first.
        vm.prank(alice);
        underlying.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        // Now measure bob's deposit.
        vm.prank(bob);
        underlying.approve(address(vault), DEPOSIT_AMOUNT);

        vm.prank(bob);
        vm.startSnapshotGas("ERC4626.deposit.subsequent");
        vault.deposit(DEPOSIT_AMOUNT, bob);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertLt(gasUsed, GAS_BOUND_DEPOSIT, "ERC4626.deposit.subsequent gas regression");
    }

    /// @notice Gas cost of withdrawing assets.
    function test_Gas_Withdraw() public {
        vm.prank(alice);
        underlying.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(alice);
        vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 withdrawAmount = 50e18;
        vm.prank(alice);
        vm.startSnapshotGas("ERC4626.withdraw");
        vault.withdraw(withdrawAmount, alice, alice);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertLt(gasUsed, GAS_BOUND_WITHDRAW, "ERC4626.withdraw gas regression");
    }

    /// @notice Gas cost of redeeming shares.
    function test_Gas_Redeem() public {
        vm.prank(alice);
        underlying.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(alice);
        uint256 shares = vault.deposit(DEPOSIT_AMOUNT, alice);

        uint256 redeemShares = shares / 2;
        vm.prank(alice);
        vm.startSnapshotGas("ERC4626.redeem");
        vault.redeem(redeemShares, alice, alice);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertLt(gasUsed, GAS_BOUND_REDEEM, "ERC4626.redeem gas regression");
    }
}
