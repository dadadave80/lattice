// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC3643TestBase} from "@lattice-test/base/ERC3643TestBase.sol";
import {IAgentRole} from "@lattice/interfaces/tokens/erc3643/IAgentRole.sol";
import {IERC3643} from "@lattice/interfaces/tokens/erc3643/IERC3643.sol";
import {Test} from "forge-std/Test.sol";

contract ERC3643AccountingHandler is Test {
    IERC3643 public token;
    address[2] public wallets;
    uint256 public minted;
    uint256 public burned;

    constructor(IERC3643 token_, address alice, address bob) {
        token = token_;
        wallets = [alice, bob];
    }

    function mint(uint256 who, uint256 amount) external {
        amount = bound(amount, 0, 1_000_000);
        token.mint(wallets[who % 2], amount);
        minted += amount;
    }

    function burn(uint256 who, uint256 amount) external {
        address wallet = wallets[who % 2];
        amount = bound(amount, 0, token.balanceOf(wallet));
        token.burn(wallet, amount);
        burned += amount;
    }

    function force(uint256 who, uint256 amount) external {
        who %= 2;
        amount = bound(amount, 0, token.balanceOf(wallets[who]));
        token.forcedTransfer(wallets[who], wallets[1 - who], amount);
    }

    function transfer(uint256 who, uint256 amount) external {
        who %= 2;
        amount = bound(amount, 0, token.balanceOf(wallets[who]));
        vm.prank(wallets[who]);
        // Pause/full/partial freezes intentionally make some ordinary actions fail.
        try token.transfer(wallets[1 - who], amount) {} catch {}
    }

    function approvedSpend(uint256 who, uint256 approved, uint256 amount) external {
        who %= 2;
        approved = bound(approved, 0, 1_000_000);
        amount = bound(amount, 0, token.balanceOf(wallets[who]));
        vm.prank(wallets[who]);
        token.approve(address(this), approved);
        try token.transferFrom(wallets[who], wallets[1 - who], amount) {} catch {}
    }

    function partialFreeze(uint256 who, uint256 amount, bool thaw) external {
        address wallet = wallets[who % 2];
        uint256 frozen = token.getFrozenTokens(wallet);
        if (thaw) token.unfreezePartialTokens(wallet, bound(amount, 0, frozen));
        else token.freezePartialTokens(wallet, bound(amount, 0, token.balanceOf(wallet) - frozen));
    }

    function fullFreeze(uint256 who, bool frozen) external {
        token.setAddressFrozen(wallets[who % 2], frozen);
    }

    function paused(bool pause_) external {
        if (pause_) token.pause();
        else token.unpause();
    }
}

contract ERC3643AccountingInvariant is ERC3643TestBase {
    ERC3643AccountingHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new ERC3643AccountingHandler(token, alice, bob);
        IAgentRole(diamond).addAgent(address(handler));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_BalancesSupplyAndPartialFreezesRemainConsistent() public view {
        assertEq(token.balanceOf(alice) + token.balanceOf(bob), token.totalSupply());
        assertEq(token.totalSupply(), 1100 + handler.minted() - handler.burned());
        assertLe(token.getFrozenTokens(alice), token.balanceOf(alice));
        assertLe(token.getFrozenTokens(bob), token.balanceOf(bob));
    }
}
