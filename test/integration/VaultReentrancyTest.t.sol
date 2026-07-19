// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title VaultReentrancyTest
/// @notice Read-only-reentrancy regression for the VaultCore <-> StrategyManager boundary.
/// @dev `VaultCore.totalAssets()` staticcalls the external StrategyManager. During
///      `rebalance()`, a (malicious) strategy's `withdraw` callback can re-enter the vault's
///      `deposit`/`redeem` while idle/allocated balances are mid-update, mispricing shares.
///      The vault must reject share-price-sensitive entry points while the manager is mid-rebalance.

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {StrategyManager} from "@lattice/defi/StrategyManager.sol";
import {VaultCore} from "@lattice/defi/VaultCore.sol";
import {StrategyManagerLib} from "@lattice/defi/libraries/StrategyManagerLib.sol";
import {VaultCoreLib} from "@lattice/defi/libraries/VaultCoreLib.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IStrategy} from "@lattice/interfaces/external/yearn/IStrategy.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC4626} from "@lattice/tokens/ERC4626/ERC4626.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal mintable ERC-20 used as the vault's underlying asset.
contract RAsset {
    string public name = "Reentrancy Asset";
    string public symbol = "RAST";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @notice Flattens the composable {ERC20} share facet, the {ERC4626} vault facet, and the {VaultCore} strategy
///         facet into one mock; the strategy-aware / rebalance-guarded {VaultCore} mutators win the clashes.
contract RVault is ERC20, ERC4626, VaultCore {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(ERC20, ERC4626, VaultCore) returns (bytes memory) {}

    function initialize(address asset_, address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ERC20Lib.__ERC20_init("Vault Share", "vSHARE");
        ERC4626Lib.__ERC4626_init(asset_, 0);
        VaultCoreLib.__VaultCore_init();
        InitializableLib.postInitializer(s);
    }

    /// @dev Resolves the `decimals()` clash between the flattened {ERC20} and {ERC4626} facets.
    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return ERC4626.decimals();
    }

    /// @dev Resolves the `totalAssets()` clash — the strategy-aware {VaultCore} variant wins.
    function totalAssets() public view override(ERC4626, VaultCore) returns (uint256) {
        return VaultCore.totalAssets();
    }

    /// @dev The rebalance-guarded {VaultCore} mutators win over the base {ERC4626} variants.
    function deposit(uint256 assets, address receiver) public override(ERC4626, VaultCore) returns (uint256) {
        return VaultCore.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override(ERC4626, VaultCore) returns (uint256) {
        return VaultCore.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override(ERC4626, VaultCore)
        returns (uint256)
    {
        return VaultCore.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override(ERC4626, VaultCore)
        returns (uint256)
    {
        return VaultCore.redeem(shares, receiver, owner);
    }
}

contract RManager is StrategyManager {
    function initialize(address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        StrategyManagerLib.__StrategyManager_init();
        InitializableLib.postInitializer(s);
    }
}

/// @notice Strategy that, when armed, re-enters the vault's `deposit` from inside `withdraw`
///         (the call the manager makes during rebalance to recall over-allocated funds).
contract ReentrantStrategy is IStrategy {
    RAsset public immutable assetToken;
    RVault public vault;
    bool public attack;

    constructor(RAsset _asset) {
        assetToken = _asset;
    }

    function setVault(RVault _v) external {
        vault = _v;
    }

    function setAttack(bool _a) external {
        attack = _a;
    }

    function asset() external view override returns (address) {
        return address(assetToken);
    }

    function totalAssetsManaged() external view override returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    function withdraw(uint256 amount, address to) external override returns (uint256) {
        if (attack) {
            uint256 amt = 1e18;
            assetToken.mint(address(this), amt);
            assetToken.approve(address(vault), amt);
            // Re-enter the vault mid-rebalance: must be rejected.
            vault.deposit(amt, address(this));
        }
        assetToken.transfer(to, amount);
        return amount;
    }
}

contract VaultReentrancyTest is Test {
    RAsset asset;
    RVault vault;
    RManager mgr;
    ReentrantStrategy strat;

    address admin = address(0xAD);
    address user = address(0xA1);
    uint256 constant DEPOSIT = 1_000e18;

    function setUp() public {
        asset = new RAsset();
        vault = new RVault();
        vault.initialize(address(asset), admin);
        mgr = new RManager();
        mgr.initialize(admin);
        strat = new ReentrantStrategy(asset);
        strat.setVault(vault);

        vm.prank(admin);
        vault.setStrategyManager(address(mgr));
        vm.startPrank(admin);
        mgr.setVault(address(vault));
        mgr.addStrategy(address(strat), 10_000); // 100% target
        vm.stopPrank();

        // User deposits, then a clean rebalance pushes all funds into the strategy.
        asset.mint(user, DEPOSIT);
        vm.startPrank(user);
        asset.approve(address(vault), DEPOSIT);
        vault.deposit(DEPOSIT, user);
        vm.stopPrank();
        mgr.rebalance();
    }

    /// @notice A deposit re-entered from a strategy callback during rebalance must revert.
    function test_DepositReentryDuringRebalanceReverts() public {
        strat.setAttack(true);
        // Set target to 0 so the strategy is over-allocated and `withdraw` is invoked in pass 1.
        vm.prank(admin);
        mgr.updateStrategyTarget(address(strat), 0);

        vm.expectRevert(IVaultCore.VaultCoreManagerRebalancing.selector);
        mgr.rebalance();
    }

    /// @notice Normal deposits/redeems are unaffected when no rebalance is in progress.
    function test_NormalDepositRedeemStillWork() public {
        asset.mint(user, DEPOSIT);
        vm.startPrank(user);
        asset.approve(address(vault), DEPOSIT);
        uint256 shares = vault.deposit(DEPOSIT, user);
        uint256 out = vault.redeem(shares, user, user);
        vm.stopPrank();
        assertGt(out, 0, "normal redeem returns assets");
    }
}
