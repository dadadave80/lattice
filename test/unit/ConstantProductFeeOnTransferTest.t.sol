// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ConstantProduct} from "@lattice/amm/ConstantProduct.sol";
import {ConstantProductLib} from "@lattice/amm/libraries/ConstantProductLib.sol";
import {IConstantProduct} from "@lattice/interfaces/amm/IConstantProduct.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                          FEE-ON-TRANSFER TOKEN
//////////////////////////////////////////////////////////////////////////*//

/// @notice Deflationary ERC-20 that burns `FEE_BPS` (1%) on every transfer and
///         transferFrom. The recipient receives `amount - fee`, so a naive pool
///         that credits the requested amount to reserves will overstate its real
///         holdings.
contract FeeOnTransferToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice Transfer fee in basis points (1%).
    uint256 public constant FEE_BPS = 100;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function _transferWithFee(address from, address to, uint256 amount) private {
        uint256 fee = (amount * FEE_BPS) / 10000;
        uint256 net = amount - fee;
        balanceOf[from] -= amount;
        // Burn the fee.
        totalSupply -= fee;
        balanceOf[to] += net;
        emit Transfer(from, to, net);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transferWithFee(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        _transferWithFee(from, to, amount);
        return true;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               STANDARD TOKEN
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal standard (non-deflationary) ERC-20 for the pair counterpart.
contract PlainERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               MOCK CONTRACT
//////////////////////////////////////////////////////////////////////////*//

contract MockCPFoT is ConstantProduct, AccessControl {
    function initialize(address token0_, address token1_, address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ConstantProductLib.__ConstantProduct_init(token0_, token1_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId_) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId_);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                   TESTS
//////////////////////////////////////////////////////////////////////////*//

/// @title ConstantProductFeeOnTransferTest
/// @notice Verifies the AMM credits the ACTUAL received balance delta (not the
///         requested amount) when a fee-on-transfer / deflationary token is used,
///         keeping `reserve <= balanceOf(pool)` and preserving solvency for the
///         honest counter-token.
contract ConstantProductFeeOnTransferTest is Test {
    MockCPFoT pool;
    FeeOnTransferToken fot;
    PlainERC20 plain;

    // Sorted handles.
    address t0;
    address t1;
    bool fotIsToken0;

    address admin = address(0xA11CE);
    address alice = address(0xA11CE2);
    address bob = address(0xB0B);

    function setUp() public {
        fot = new FeeOnTransferToken("FeeOnTransfer", "FOT");
        plain = new PlainERC20("Plain", "PLN");

        if (address(fot) < address(plain)) {
            (t0, t1) = (address(fot), address(plain));
            fotIsToken0 = true;
        } else {
            (t0, t1) = (address(plain), address(fot));
            fotIsToken0 = false;
        }

        pool = new MockCPFoT();
        pool.initialize(t0, t1, admin);

        fot.mint(alice, 1_000_000e18);
        plain.mint(alice, 1_000_000e18);
        fot.mint(bob, 1_000_000e18);
        plain.mint(bob, 1_000_000e18);
    }

    /// @dev Returns (reserveFot, reservePlain) from the sorted reserves.
    function _reserves() internal view returns (uint256 reserveFot, uint256 reservePlain) {
        (uint256 r0, uint256 r1,) = pool.getReserves();
        return fotIsToken0 ? (r0, r1) : (r1, r0);
    }

    /// @notice After adding liquidity with a fee-on-transfer token, the recorded
    ///         FOT reserve must not exceed the pool's real FOT balance.
    ///         Pre-fix the pool credits the requested amount (overstating reserves);
    ///         post-fix it credits the actual delta.
    function test_AddLiquidityCreditsActualReceivedForFoT() public {
        uint256 addFot = 100e18;
        uint256 addPlain = 100e18;

        vm.startPrank(alice);
        fot.approve(address(pool), addFot);
        plain.approve(address(pool), addPlain);
        pool.addLiquidity(fotIsToken0 ? addFot : addPlain, fotIsToken0 ? addPlain : addFot, 0, 0, alice);
        vm.stopPrank();

        (uint256 reserveFot,) = _reserves();
        uint256 poolFotBalance = fot.balanceOf(address(pool));

        // Core invariant: reserves must never claim more than the pool actually holds.
        assertLe(reserveFot, poolFotBalance, "FOT reserve overstates real pool balance after addLiquidity");

        // With a 1% transfer fee, the pool received 99e18, so the reserve must
        // reflect the actual delta, not the requested 100e18.
        assertEq(reserveFot, poolFotBalance, "FOT reserve should equal the actual received balance");
        assertEq(reserveFot, 99e18, "FOT reserve should be the net-of-fee amount");
    }

    /// @notice After a swap that sends the fee-on-transfer token IN, the input-side
    ///         reserve must not exceed the pool's real balance of that token, and
    ///         the global solvency invariant (reserve <= balanceOf) must hold for
    ///         both tokens.
    function test_SwapCreditsActualReceivedForFoT() public {
        // Seed the pool with a balanced FOT/plain position.
        // Use addLiquidity twice-net amounts so both sides are well funded.
        vm.startPrank(alice);
        fot.approve(address(pool), 1000e18);
        plain.approve(address(pool), 1000e18);
        pool.addLiquidity(fotIsToken0 ? 1000e18 : 1000e18, fotIsToken0 ? 1000e18 : 1000e18, 0, 0, alice);
        vm.stopPrank();

        // Bob swaps FOT in for plain out.
        uint256 amountIn = 10e18;
        vm.startPrank(bob);
        fot.approve(address(pool), amountIn);
        // zeroForOne true if FOT is token0.
        pool.swapExactTokensForTokens(amountIn, 0, fotIsToken0, bob);
        vm.stopPrank();

        // Solvency invariant for BOTH tokens.
        (uint256 r0, uint256 r1,) = pool.getReserves();
        assertLe(r0, _balanceOfToken0(), "reserve0 overstates pool balance after FOT swap");
        assertLe(r1, _balanceOfToken1(), "reserve1 overstates pool balance after FOT swap");
    }

    /// @notice The honest counter-token cannot be drained: after a FOT-in swap, a
    ///         later full liquidity withdrawal must succeed (pool stays solvent on
    ///         the plain side). Pre-fix, overstated reserves let the plain side be
    ///         over-credited relative to real balances, which can break later
    ///         transfers out.
    function test_HonestSideRemainsSolventAfterFoTSwap() public {
        vm.startPrank(alice);
        fot.approve(address(pool), 1000e18);
        plain.approve(address(pool), 1000e18);
        (,, uint256 lp) = pool.addLiquidity(1000e18, 1000e18, 0, 0, alice);
        vm.stopPrank();

        // Several FOT-in swaps by bob.
        for (uint256 i = 0; i < 3; ++i) {
            vm.startPrank(bob);
            fot.approve(address(pool), 5e18);
            pool.swapExactTokensForTokens(5e18, 0, fotIsToken0, bob);
            vm.stopPrank();
        }

        // Invariant must hold for both reserves.
        (uint256 r0, uint256 r1,) = pool.getReserves();
        assertLe(r0, _balanceOfToken0(), "reserve0 > balance after swaps");
        assertLe(r1, _balanceOfToken1(), "reserve1 > balance after swaps");

        // Alice can withdraw her full LP position without reverting.
        vm.prank(alice);
        pool.removeLiquidity(lp, 0, 0, alice);
    }

    function _balanceOfToken0() internal view returns (uint256) {
        return fotIsToken0 ? fot.balanceOf(address(pool)) : plain.balanceOf(address(pool));
    }

    function _balanceOfToken1() internal view returns (uint256) {
        return fotIsToken0 ? plain.balanceOf(address(pool)) : fot.balanceOf(address(pool));
    }
}
