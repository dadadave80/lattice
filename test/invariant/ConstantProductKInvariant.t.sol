// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ConstantProduct} from "@lattice/amm/ConstantProduct.sol";
import {ConstantProductLib} from "@lattice/amm/libraries/ConstantProductLib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                               MOCK TOKENS
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal ERC-20 for AMM invariant testing.
contract AmmToken {
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
//                               MOCK POOL
//////////////////////////////////////////////////////////////////////////*//

/// @notice Mock combining ConstantProduct + AccessControl.
contract MockAmmPool is ConstantProduct, AccessControl {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(ConstantProduct, AccessControl) returns (bytes memory) {}

    function initialize(address tokenA_, address tokenB_, address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ConstantProductLib.__ConstantProduct_init(tokenA_, tokenB_);
        InitializableLib.postInitializer(s);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Handler for ConstantProduct K and LP supply invariant tests.
contract ConstantProductHandler is Test {
    MockAmmPool public pool;
    AmmToken public token0;
    AmmToken public token1;

    address[3] public actors;
    address[] internal _lpProviders;
    mapping(address => bool) internal _hasProvided;

    /// @notice Set to true if any swap ever decreased K — remains true forever.
    bool public kViolated;
    /// @notice K value immediately after the most recent swap (0 if no swaps yet).
    uint256 public kAfterLastSwap;

    uint256 constant INITIAL_MINT = 10_000_000e18;
    uint256 constant MINIMUM_LIQUIDITY = 1000;

    constructor(MockAmmPool pool_, AmmToken token0_, AmmToken token1_) {
        pool = pool_;
        token0 = token0_;
        token1 = token1_;

        actors[0] = address(0xC1);
        actors[1] = address(0xC2);
        actors[2] = address(0xC3);

        // Mint generous amounts and pre-approve.
        for (uint256 i; i < actors.length; ++i) {
            token0.mint(actors[i], INITIAL_MINT);
            token1.mint(actors[i], INITIAL_MINT);
            vm.prank(actors[i]);
            token0.approve(address(pool), type(uint256).max);
            vm.prank(actors[i]);
            token1.approve(address(pool), type(uint256).max);
        }
    }

    function lpProviders() external view returns (address[] memory) {
        return _lpProviders;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _touchLp(address a) internal {
        if (!_hasProvided[a]) {
            _hasProvided[a] = true;
            _lpProviders.push(a);
        }
    }

    function _currentK() internal view returns (uint256) {
        (uint256 r0, uint256 r1,) = pool.getReserves();
        return r0 * r1;
    }

    function addLiquidity(uint256 actorSeed, uint256 amount0, uint256 amount1) external {
        address actor = _actor(actorSeed);
        amount0 = bound(amount0, 1000, token0.balanceOf(actor) / 2 + 1);
        amount1 = bound(amount1, 1000, token1.balanceOf(actor) / 2 + 1);
        _touchLp(actor);
        vm.prank(actor);
        pool.addLiquidity(amount0, amount1, 0, 0, actor);
    }

    function removeLiquidity(uint256 actorSeed, uint256 lpAmount) external {
        address actor = _actor(actorSeed);
        uint256 lpBal = pool.lpBalanceOf(actor);
        if (lpBal == 0) return;
        lpAmount = bound(lpAmount, 1, lpBal);
        vm.prank(actor);
        pool.removeLiquidity(lpAmount, 0, 0, actor);
    }

    function swapForward(uint256 actorSeed, uint256 amountIn) external {
        address actor = _actor(actorSeed);
        (uint256 r0, uint256 r1,) = pool.getReserves();
        if (r0 == 0 || r1 == 0) return;
        uint256 bal = token0.balanceOf(actor);
        if (bal == 0) return;
        amountIn = bound(amountIn, 1, bal / 2 + 1);

        uint256 kBefore = _currentK();
        vm.prank(actor);
        pool.swapExactTokensForTokens(amountIn, 0, true, actor);
        uint256 kAfter = _currentK();
        // Record the monotonic K violation as a persistent ghost.
        if (kAfter < kBefore) kViolated = true;
        kAfterLastSwap = kAfter;
    }

    function swapBackward(uint256 actorSeed, uint256 amountIn) external {
        address actor = _actor(actorSeed);
        (uint256 r0, uint256 r1,) = pool.getReserves();
        if (r0 == 0 || r1 == 0) return;
        uint256 bal = token1.balanceOf(actor);
        if (bal == 0) return;
        amountIn = bound(amountIn, 1, bal / 2 + 1);

        uint256 kBefore = _currentK();
        vm.prank(actor);
        pool.swapExactTokensForTokens(amountIn, 0, false, actor);
        uint256 kAfter = _currentK();
        if (kAfter < kBefore) kViolated = true;
        kAfterLastSwap = kAfter;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               INVARIANT TEST
//////////////////////////////////////////////////////////////////////////*//

/// @title ConstantProductKInvariant
/// @notice Invariant: K never decreases after a swap (fees cause it to monotonically increase).
///         Also: total LP supply matches the sum of all LP balances (excluding locked MINIMUM_LIQUIDITY).
contract ConstantProductKInvariant is Test {
    MockAmmPool internal pool;
    AmmToken internal token0;
    AmmToken internal token1;
    ConstantProductHandler internal handler;

    uint256 constant MINIMUM_LIQUIDITY = 1000;

    function setUp() public {
        AmmToken tA = new AmmToken("TkA", "TKA");
        AmmToken tB = new AmmToken("TkB", "TKB");

        // Determine canonical token order to match pool's sorting.
        if (address(tA) < address(tB)) {
            token0 = tA;
            token1 = tB;
        } else {
            token0 = tB;
            token1 = tA;
        }

        pool = new MockAmmPool();
        pool.initialize(address(tA), address(tB), address(this));

        handler = new ConstantProductHandler(pool, token0, token1);
        targetContract(address(handler));
    }

    /// @notice K must never decrease as a result of a swap.
    /// Uses a persistent ghost flag set inside the handler to avoid false positives from
    /// liquidity removals that legitimately reduce K.
    function invariant_KMonotonicOnSwap() public view {
        assertFalse(handler.kViolated(), "K decreased after swap");
    }

    /// @notice totalLpSupply == sum of LP balances for all providers + MINIMUM_LIQUIDITY locked at address(1).
    function invariant_LpSupplyConsistent() public view {
        address[] memory providers = handler.lpProviders();
        uint256 sum = pool.lpBalanceOf(address(1)); // locked MINIMUM_LIQUIDITY
        for (uint256 i; i < providers.length; ++i) {
            sum += pool.lpBalanceOf(providers[i]);
        }
        assertEq(sum, pool.totalLpSupply(), "LP supply sum mismatch");
    }
}
