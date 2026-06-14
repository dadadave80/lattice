// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                            MOCK TOKENS
//////////////////////////////////////////////////////////////////////////*//

/// @notice Standard mintable ERC-20 returning a bool from transfer/approve.
contract MockERC20 {
    string public name = "Mock";
    string public symbol = "MCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external virtual returns (bool) {
        require(balanceOf[msg.sender] >= amount, "bal");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "bal");
        require(allowance[from][msg.sender] >= amount, "allow");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @notice USDT-style token: approve reverts unless the current allowance is 0
///         (the canonical "non-zero to non-zero approval reverts" weirdness).
contract MockApprovalRaceToken is MockERC20 {
    function approve(address spender, uint256 amount) external override returns (bool) {
        require(amount == 0 || allowance[msg.sender][spender] == 0, "approve-race");
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @notice Reward token that taxes 10% on every transfer (fee-on-transfer).
contract MockFeeOnTransferToken is MockERC20 {
    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "bal");
        uint256 fee = amount / 10;
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount - fee;
        balanceOf[address(0xdead)] += fee;
        return true;
    }
}

/// @notice Token whose transfer returns no data (non-standard, like old BNB).
contract MockNoReturnToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "bal");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                       HARNESS (exposes the library)
//////////////////////////////////////////////////////////////////////////*//

/// @notice Thin harness so the pure library functions are callable from tests and
///         `msg.sender`/`address(this)` resolve to the harness (mirrors how an adapter
///         facet would call the library).
contract AdapterBaseHarness {
    function forceApprove(address token, address spender, uint256 amount) external {
        AdapterBaseLib.forceApprove(token, spender, amount);
    }

    function forwardRewardRaw(address rewardToken, address recipient) external returns (uint256) {
        return AdapterBaseLib.forwardRewardRaw(rewardToken, recipient);
    }

    function transferHonest(address token, address to, uint256 amount) external returns (uint256) {
        return AdapterBaseLib.transferHonest(token, to, amount);
    }

    function balanceOf(address token) external view returns (uint256) {
        return AdapterBaseLib.balanceOfSelf(token);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                              TEST SUITE
//////////////////////////////////////////////////////////////////////////*//

contract AdapterBaseLibTest is Test {
    AdapterBaseHarness harness;
    address spender = address(0xBEEF);
    address recipient = address(0xCAFE);

    function setUp() public {
        harness = new AdapterBaseHarness();
    }

    function test_ForceApprove_SetsExactAllowance() public {
        MockERC20 t = new MockERC20();
        harness.forceApprove(address(t), spender, 500);
        assertEq(t.allowance(address(harness), spender), 500, "exact allowance");
    }

    function test_ForceApprove_ResetsBeforeSettingOnRaceToken() public {
        // USDT-style: must zero the allowance before setting a new non-zero value.
        MockApprovalRaceToken t = new MockApprovalRaceToken();
        harness.forceApprove(address(t), spender, 100);
        // Second call would revert on a naive approve(non-zero) — forceApprove zeroes first.
        harness.forceApprove(address(t), spender, 250);
        assertEq(t.allowance(address(harness), spender), 250, "re-approve via reset");
    }

    function test_ForceApprove_HandlesNoReturnToken() public {
        MockNoReturnToken t = new MockNoReturnToken();
        harness.forceApprove(address(t), spender, 777);
        assertEq(t.allowance(address(harness), spender), 777, "no-return approve ok");
    }

    function test_ForwardRewardRaw_ForwardsFullBalance() public {
        MockERC20 r = new MockERC20();
        r.mint(address(harness), 1_000);
        uint256 forwarded = harness.forwardRewardRaw(address(r), recipient);
        assertEq(forwarded, 1_000, "real forwarded amount");
        assertEq(r.balanceOf(recipient), 1_000, "recipient received");
        assertEq(r.balanceOf(address(harness)), 0, "adapter drained");
    }

    function test_ForwardRewardRaw_ZeroBalanceIsNoOp() public {
        MockERC20 r = new MockERC20();
        uint256 forwarded = harness.forwardRewardRaw(address(r), recipient);
        assertEq(forwarded, 0, "nothing to forward");
    }

    function test_ForwardRewardRaw_FeeOnTransferReportsRealDelta() public {
        // A bad reward token must not over-report; we measure the recipient's real gain.
        MockFeeOnTransferToken r = new MockFeeOnTransferToken();
        r.mint(address(harness), 1_000);
        uint256 forwarded = harness.forwardRewardRaw(address(r), recipient);
        assertEq(r.balanceOf(recipient), 900, "recipient nets 90%");
        assertEq(forwarded, 900, "reports real received delta, not 1000");
    }

    function test_TransferHonest_ReturnsRealAmountOnShortfall() public {
        // Request more than held: transfer the available balance, return the real amount.
        MockERC20 t = new MockERC20();
        t.mint(address(harness), 400);
        uint256 sent = harness.transferHonest(address(t), recipient, 1_000);
        assertEq(sent, 400, "honest: capped at available");
        assertEq(t.balanceOf(recipient), 400, "recipient got available");
    }

    function test_TransferHonest_FullWhenSufficient() public {
        MockERC20 t = new MockERC20();
        t.mint(address(harness), 1_000);
        uint256 sent = harness.transferHonest(address(t), recipient, 600);
        assertEq(sent, 600, "exact requested");
        assertEq(t.balanceOf(address(harness)), 400, "remainder kept");
    }
}
