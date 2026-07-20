// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal mintable ERC-20 used by fuzz tests.
contract FuzzERC20 is ERC20, Initializable {
    function initialize(string memory name_, string memory symbol_) external initializer {
        ERC20Lib.__ERC20_init(name_, symbol_);
    }

    function mint(address to, uint256 value) external {
        ERC20Lib._mint(to, value);
    }
}

/// @title ERC20TransferFuzz
contract ERC20TransferFuzz is Test {
    FuzzERC20 token;

    address constant SENDER = address(0x1111);
    address constant RECIPIENT = address(0x2222);

    function setUp() public {
        token = new FuzzERC20();
        token.initialize("Fuzz Token", "FZZ");
    }

    /// @notice Transferring `amount` conserves balances and leaves totalSupply unchanged.
    function testFuzz_TransferConservesBalance(uint256 amount) public {
        // Bound to a sane range; uint96 avoids totalSupply overflow concerns.
        amount = bound(amount, 1, type(uint96).max);

        token.mint(SENDER, amount);

        uint256 supplyBefore = token.totalSupply();
        uint256 senderBefore = token.balanceOf(SENDER);
        uint256 recipientBefore = token.balanceOf(RECIPIENT);

        vm.prank(SENDER);
        token.transfer(RECIPIENT, amount);

        assertEq(token.totalSupply(), supplyBefore, "totalSupply must not change");
        assertEq(token.balanceOf(SENDER), senderBefore - amount, "sender balance decreased by amount");
        assertEq(token.balanceOf(RECIPIENT), recipientBefore + amount, "recipient balance increased by amount");
    }

    /// @notice Transferring 0 tokens still emits a Transfer event (ERC-20 spec requirement).
    function testFuzz_TransferZeroEmitsEvent(address to) public {
        vm.assume(to != address(0));

        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(SENDER, to, 0);

        vm.prank(SENDER);
        token.transfer(to, 0);
    }

    /// @notice Transferring from self to self leaves the balance identical.
    function testFuzz_TransferToSelfIsNoop(uint256 amount) public {
        amount = bound(amount, 0, type(uint128).max);

        token.mint(SENDER, amount);
        uint256 balanceBefore = token.balanceOf(SENDER);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(SENDER);
        token.transfer(SENDER, amount);

        assertEq(token.balanceOf(SENDER), balanceBefore, "self-transfer must not change balance");
        assertEq(token.totalSupply(), supplyBefore, "self-transfer must not change totalSupply");
    }

    /// @notice transferFrom consumes exactly `spendAmt` from the allowance.
    function testFuzz_TransferFromConsumesAllowance(uint256 approveAmt, uint256 spendAmt) public {
        // spendAmt <= approveAmt < max (infinite-allowance sentinel excluded)
        approveAmt = bound(approveAmt, 1, type(uint256).max - 1);
        spendAmt = bound(spendAmt, 0, approveAmt);

        token.mint(SENDER, approveAmt);

        // SENDER approves this contract to spend on its behalf.
        vm.prank(SENDER);
        token.approve(address(this), approveAmt);

        uint256 allowanceBefore = token.allowance(SENDER, address(this));

        token.transferFrom(SENDER, RECIPIENT, spendAmt);

        assertEq(token.allowance(SENDER, address(this)), allowanceBefore - spendAmt, "allowance decreases by spendAmt");
    }
}
