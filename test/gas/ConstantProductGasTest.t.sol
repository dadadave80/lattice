// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ConstantProduct} from "@lattice/amm/ConstantProduct.sol";
import {ConstantProductLib} from "@lattice/amm/libraries/ConstantProductLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal ERC-20 used by ConstantProduct gas tests.
contract GasTestERC20 {
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

/// @notice Mock Diamond contract combining ConstantProduct and AccessControl for gas tests.
contract GasConstantProduct is ConstantProduct, AccessControl {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(ConstantProduct, AccessControl) returns (bytes memory) {}

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

/// @title ConstantProductGasTest
/// @notice Gas snapshot tests for hot paths in the ConstantProduct AMM module.
contract ConstantProductGasTest is Test {
    GasConstantProduct pool;
    GasTestERC20 tokenA;
    GasTestERC20 tokenB;
    GasTestERC20 token0;
    GasTestERC20 token1;

    address admin = address(0xA11CE);
    address alice = address(0xA11CE2);
    address bob = address(0xB0B);

    uint256 constant INITIAL_LIQUIDITY_0 = 100e18;
    uint256 constant INITIAL_LIQUIDITY_1 = 400e18;

    // Generous upper bounds (~2× expected) so tests do not flicker.
    uint256 constant GAS_BOUND_ADD_LIQUIDITY = 650_000;
    uint256 constant GAS_BOUND_SWAP = 600_000;
    uint256 constant GAS_BOUND_REMOVE_LIQUIDITY = 500_000;

    function setUp() public {
        tokenA = new GasTestERC20("TokenA", "TKA");
        tokenB = new GasTestERC20("TokenB", "TKB");

        if (address(tokenA) < address(tokenB)) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }

        pool = new GasConstantProduct();
        pool.initialize(address(tokenA), address(tokenB), admin);

        token0.mint(alice, 1_000_000e18);
        token1.mint(alice, 1_000_000e18);
        token0.mint(bob, 1_000_000e18);
        token1.mint(bob, 1_000_000e18);
    }

    /// @notice Gas cost of the first addLiquidity call (sqrt math + MINIMUM_LIQUIDITY lock).
    function test_Gas_AddLiquidityFirst() public {
        vm.startPrank(alice);
        token0.approve(address(pool), INITIAL_LIQUIDITY_0);
        token1.approve(address(pool), INITIAL_LIQUIDITY_1);

        vm.startSnapshotGas("ConstantProduct.addLiquidity.first");
        pool.addLiquidity(INITIAL_LIQUIDITY_0, INITIAL_LIQUIDITY_1, 0, 0, alice);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertLt(gasUsed, GAS_BOUND_ADD_LIQUIDITY, "ConstantProduct.addLiquidity.first gas regression");
    }

    /// @notice Gas cost of a subsequent addLiquidity call (ratio-proportional math).
    function test_Gas_AddLiquiditySubsequent() public {
        // Seed pool with first deposit.
        vm.startPrank(alice);
        token0.approve(address(pool), INITIAL_LIQUIDITY_0);
        token1.approve(address(pool), INITIAL_LIQUIDITY_1);
        pool.addLiquidity(INITIAL_LIQUIDITY_0, INITIAL_LIQUIDITY_1, 0, 0, alice);
        vm.stopPrank();

        // Measure bob's deposit.
        vm.startPrank(bob);
        token0.approve(address(pool), 10e18);
        token1.approve(address(pool), 40e18);

        vm.startSnapshotGas("ConstantProduct.addLiquidity.subsequent");
        pool.addLiquidity(10e18, 40e18, 0, 0, bob);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertLt(gasUsed, GAS_BOUND_ADD_LIQUIDITY, "ConstantProduct.addLiquidity.subsequent gas regression");
    }

    /// @notice Gas cost of swapExactTokensForTokens.
    function test_Gas_Swap() public {
        // Seed pool.
        vm.startPrank(alice);
        token0.approve(address(pool), INITIAL_LIQUIDITY_0);
        token1.approve(address(pool), INITIAL_LIQUIDITY_1);
        pool.addLiquidity(INITIAL_LIQUIDITY_0, INITIAL_LIQUIDITY_1, 0, 0, alice);
        vm.stopPrank();

        uint256 swapIn = 1e18;
        vm.startPrank(bob);
        token0.approve(address(pool), swapIn);

        vm.startSnapshotGas("ConstantProduct.swapExactTokensForTokens");
        pool.swapExactTokensForTokens(swapIn, 0, true, bob);
        uint256 gasUsed = vm.stopSnapshotGas();
        vm.stopPrank();

        assertLt(gasUsed, GAS_BOUND_SWAP, "ConstantProduct.swapExactTokensForTokens gas regression");
    }

    /// @notice Gas cost of removeLiquidity.
    function test_Gas_RemoveLiquidity() public {
        // Seed pool.
        vm.startPrank(alice);
        token0.approve(address(pool), INITIAL_LIQUIDITY_0);
        token1.approve(address(pool), INITIAL_LIQUIDITY_1);
        (,, uint256 aliceLp) = pool.addLiquidity(INITIAL_LIQUIDITY_0, INITIAL_LIQUIDITY_1, 0, 0, alice);
        vm.stopPrank();

        vm.prank(alice);
        vm.startSnapshotGas("ConstantProduct.removeLiquidity");
        pool.removeLiquidity(aliceLp, 0, 0, alice);
        uint256 gasUsed = vm.stopSnapshotGas();

        assertLt(gasUsed, GAS_BOUND_REMOVE_LIQUIDITY, "ConstantProduct.removeLiquidity gas regression");
    }
}
