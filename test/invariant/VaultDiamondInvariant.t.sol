// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {DeployVaultCore} from "@lattice-script/base/defi/DeployVaultCore.s.sol";
import {StrategyManagerTestBase} from "@lattice-test/base/StrategyManagerTestBase.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {StrategyManager} from "@lattice/defi/StrategyManager.sol";
import {REBALANCE_SHORTFALL_TOLERANCE} from "@lattice/defi/libraries/StrategyManagerLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IStrategyManager} from "@lattice/interfaces/defi/IStrategyManager.sol";
import {IStrategyManagerRecovery} from "@lattice/interfaces/defi/IStrategyManagerRecovery.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IVaultCoreRecovery} from "@lattice/interfaces/defi/IVaultCoreRecovery.sol";
import {IStrategy} from "@lattice/interfaces/external/yearn/IStrategy.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                 FIXTURES
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal mintable ERC-20 used as the vault asset. Only the handler mints it.
contract InvVaultAsset {
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
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
}

/// @notice Strategy that holds the vault's allocated assets and reports its live balance.
/// @dev Two frictions model real recalls: `haircut` (value lost on each withdraw, sent to `SINK`) and `liquidity`
///      (the most one withdraw pays out; the rest stays reported, an honest partial recall). `bricked` makes the
///      NAV read revert, the state a force removal recovers from. The withdraw never reverts.
contract InvStrategy is IStrategy {
    address public constant SINK = address(0xDEAD);

    InvVaultAsset public immutable token;
    uint256 public haircut;
    uint256 public liquidity = type(uint256).max;
    bool public bricked;

    constructor(InvVaultAsset token_) {
        token = token_;
    }

    function setFrictions(uint256 haircut_, uint256 liquidity_) external {
        haircut = haircut_;
        liquidity = liquidity_;
    }

    function brick() external {
        bricked = true;
    }

    /// @notice Makes the NAV read work again without returning anything: a stranded strategy offered for re-add.
    function unbrick() external {
        bricked = false;
    }

    /// @notice Unbricks and pushes everything back to `to`: the stranded funds returning after a force removal.
    function returnAll(address to) external {
        bricked = false;
        token.transfer(to, token.balanceOf(address(this)));
    }

    /// @notice Burns `amount` to the sink: a loss inside the strategy.
    function lose(uint256 amount) external {
        token.transfer(SINK, amount);
    }

    /// @notice What a withdraw of `amount` pays out and burns, without moving funds.
    function quote(uint256 amount) public view returns (uint256 sent, uint256 lost) {
        uint256 balance = token.balanceOf(address(this));
        sent = amount < liquidity ? amount : liquidity;
        if (sent > balance) sent = balance;
        lost = haircut < sent ? haircut : sent;
    }

    function asset() external view override returns (address) {
        return address(token);
    }

    function totalAssetsManaged() external view override returns (uint256) {
        require(!bricked, "strategy bricked");
        return token.balanceOf(address(this));
    }

    function withdraw(uint256 amount, address to) external override returns (uint256) {
        (uint256 sent, uint256 lost) = quote(amount);
        token.transfer(SINK, lost);
        token.transfer(to, sent - lost);
        return sent - lost;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Drives a recipe-built vault diamond and its recipe-built StrategyManager diamonds through deposits,
///         mints, exits, share transfers, strategy yield and loss, rebalances, target changes, strategy adds and
///         removals, force removals (which latch deposits on the manager), manager swaps (which latch deposits on
///         the vault when they may strand funds) and both latch clears.
/// @dev Revert-free under `fail_on_revert`: every action is bounded to a valid call, or arms the exact revert it
///      expects. A strategy is bricked and force-removed in the same action, so no call ever ends with a bricked
///      strategy registered (that would make `totalAssets()` revert in every invariant). The ghost NAV moves only
///      by what each action is expected to add or remove, independently of the vault's own accounting.
///      A swap only ever moves to a fresh spare manager, never back to an old one (whose strategies would step
///      the NAV back up); the old manager's strategies are then stranded like force-removed ones (#305).
contract VaultHandler is Test {
    IVaultCore public immutable vault;
    StrategyManager public mgr;
    InvVaultAsset public immutable asset;
    address public immutable mgrAdmin;
    address public immutable vaultAdmin;

    /// @notice Fresh managers, already pointed at the vault, that `swapManager` moves to in order.
    StrategyManager[] internal _spareManagers;
    uint256 public swaps;

    uint256 internal constant MAX_AMOUNT = 1e24;
    uint256 internal constant MAX_REGISTERED = 4;
    /// @dev Entries stop once the supply passes this, so repeated wipe-outs cannot push share math past 2^256.
    uint256 internal constant MAX_SUPPLY = 1e40;

    address[3] internal _actors;

    /// @notice Every strategy ever created: registered, removed empty, or force-removed and stranded.
    InvStrategy[] public allStrategies;
    mapping(address strategy => bool) public stranded;

    /// @notice The NAV the vault should report, moved only by each action's expected effect.
    uint256 public ghostNav;
    uint256 public ghostSharesMinted;
    uint256 public ghostSharesBurned;
    /// @notice The configured manager's own latch (set by a force removal).
    bool public ghostLatched;
    /// @notice The vault's manager-swap latch (set by a swap that may strand funds).
    bool public ghostVaultLatched;

    constructor(
        IVaultCore vault_,
        StrategyManager mgr_,
        InvVaultAsset asset_,
        address mgrAdmin_,
        address vaultAdmin_,
        StrategyManager[] memory spares
    ) {
        vault = vault_;
        mgr = mgr_;
        asset = asset_;
        mgrAdmin = mgrAdmin_;
        vaultAdmin = vaultAdmin_;
        _spareManagers = spares;
        _actors[0] = address(0xA11CE);
        _actors[1] = address(0xB0B);
        _actors[2] = address(0xCA201);
    }

    function actors() external view returns (address[3] memory) {
        return _actors;
    }

    function strategyCount() external view returns (uint256) {
        return allStrategies.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return _actors[seed % _actors.length];
    }

    /// @dev The contract named by `VaultCoreDepositsLatched` while entries are latched: the vault for its own
    ///      manager-swap latch (checked first), else the configured manager.
    function _latchHolder() internal view returns (address) {
        return ghostVaultLatched ? address(vault) : address(mgr);
    }

    /// @dev A registered strategy picked by `seed`, or address(0) when none is registered.
    function _registered(uint256 seed) internal view returns (InvStrategy) {
        address[] memory s = mgr.getStrategies();
        if (s.length == 0) return InvStrategy(address(0));
        return InvStrategy(s[seed % s.length]);
    }

    function _isRegistered(address strategy) internal view returns (bool) {
        address[] memory s = mgr.getStrategies();
        for (uint256 i; i < s.length; ++i) {
            if (s[i] == strategy) return true;
        }
        return false;
    }

    /// @dev A strategy created earlier and no longer registered, picked by `seed`: a stranded one when any exists
    ///      (so the refused re-add runs often), else any removed one, else address(0).
    function _removed(uint256 seed) internal view returns (InvStrategy fallback_) {
        uint256 n = allStrategies.length;
        for (uint256 i; i < n; ++i) {
            InvStrategy s = allStrategies[(seed % n + i) % n];
            if (_isRegistered(address(s))) continue;
            if (stranded[address(s)]) return s;
            if (address(fallback_) == address(0)) fallback_ = s;
        }
    }

    /// @notice Seeds a strategy at setup (no ghost change: it starts empty).
    function addInitialStrategy(uint16 bps) external {
        _newStrategy(bps);
    }

    function _newStrategy(uint16 bps) internal returns (InvStrategy s) {
        s = new InvStrategy(asset);
        allStrategies.push(s);
        vm.prank(mgrAdmin);
        mgr.addStrategy(address(s), bps);
    }

    // ---- Entries ----

    function deposit(uint256 actorSeed, uint256 assets) external {
        if (vault.totalSupply() > MAX_SUPPLY) return;
        address a = _actor(actorSeed);
        assets = bound(assets, 1, MAX_AMOUNT);
        asset.mint(a, assets);
        vm.prank(a);
        asset.approve(address(vault), assets);

        if (ghostLatched || ghostVaultLatched) {
            assertEq(vault.maxDeposit(a), 0, "maxDeposit open while latched");
            vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreDepositsLatched.selector, _latchHolder()));
            vm.prank(a);
            vault.deposit(assets, a);
            return;
        }

        uint256 expected = vault.previewDeposit(assets);
        vm.prank(a);
        uint256 shares = vault.deposit(assets, a);
        assertEq(shares, expected, "deposit != previewDeposit");
        assertLe(vault.previewRedeem(shares), assets, "deposit minted free shares");
        ghostNav += assets;
        ghostSharesMinted += shares;
    }

    function mint(uint256 actorSeed, uint256 shares) external {
        if (vault.totalSupply() > MAX_SUPPLY) return;
        address a = _actor(actorSeed);
        shares = bound(shares, 1, MAX_AMOUNT);

        if (ghostLatched || ghostVaultLatched) {
            assertEq(vault.maxMint(a), 0, "maxMint open while latched");
            vm.expectRevert(abi.encodeWithSelector(IVaultCore.VaultCoreDepositsLatched.selector, _latchHolder()));
            vm.prank(a);
            vault.mint(shares, a);
            return;
        }

        uint256 expected = vault.previewMint(shares);
        asset.mint(a, expected);
        vm.prank(a);
        asset.approve(address(vault), expected);
        vm.prank(a);
        uint256 assets = vault.mint(shares, a);
        assertEq(assets, expected, "mint != previewMint");
        assertGt(assets, 0, "mint took no assets");
        assertLe(vault.previewRedeem(shares), assets, "mint minted free shares");
        ghostNav += assets;
        ghostSharesMinted += shares;
    }

    // ---- Exits ----

    /// @notice Withdraws up to `maxWithdraw`; on odd seeds asks for one wei more and expects the cap to hold.
    function withdraw(uint256 actorSeed, uint256 assets) external {
        address a = _actor(actorSeed);
        uint256 maxAssets = vault.maxWithdraw(a);
        uint256 idle = vault.idleAssets();
        assertLe(maxAssets, idle, "maxWithdraw > idle");

        if (actorSeed % 2 == 1) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC4626.ERC4626ExceededMaxWithdraw.selector, a, maxAssets + 1, maxAssets)
            );
            vm.prank(a);
            vault.withdraw(maxAssets + 1, a, a);
            return;
        }

        assets = bound(assets, 0, maxAssets);
        uint256 expected = vault.previewWithdraw(assets);
        uint256 before = asset.balanceOf(a);
        vm.prank(a);
        uint256 shares = vault.withdraw(assets, a, a);
        assertEq(shares, expected, "withdraw != previewWithdraw");
        assertEq(asset.balanceOf(a) - before, assets, "withdraw paid wrong amount");
        ghostNav -= assets;
        ghostSharesBurned += shares;
    }

    /// @notice Redeems up to `maxRedeem`; on odd seeds asks for one share more and expects the cap to hold.
    function redeem(uint256 actorSeed, uint256 shares) external {
        address a = _actor(actorSeed);
        uint256 maxShares = vault.maxRedeem(a);
        uint256 idle = vault.idleAssets();

        if (actorSeed % 2 == 1) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC4626.ERC4626ExceededMaxRedeem.selector, a, maxShares + 1, maxShares)
            );
            vm.prank(a);
            vault.redeem(maxShares + 1, a, a);
            return;
        }

        shares = bound(shares, 0, maxShares);
        uint256 expected = vault.previewRedeem(shares);
        vm.prank(a);
        uint256 assets = vault.redeem(shares, a, a);
        assertEq(assets, expected, "redeem != previewRedeem");
        assertLe(assets, idle, "redeem paid more than idle");
        ghostNav -= assets;
        ghostSharesBurned += shares;
    }

    function transferShares(uint256 fromSeed, uint256 toSeed, uint256 shares) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        shares = bound(shares, 0, vault.balanceOf(from));
        vm.prank(from);
        vault.transfer(to, shares);
    }

    // ---- Value moving outside the vault's own entry points ----

    function strategyYield(uint256 strategySeed, uint256 amount) external {
        InvStrategy s = _registered(strategySeed);
        if (address(s) == address(0)) return;
        amount = bound(amount, 0, MAX_AMOUNT / 10);
        asset.mint(address(s), amount);
        ghostNav += amount;
    }

    function strategyLoss(uint256 strategySeed, uint256 amount) external {
        InvStrategy s = _registered(strategySeed);
        if (address(s) == address(0)) return;
        amount = bound(amount, 0, asset.balanceOf(address(s)));
        s.lose(amount);
        ghostNav -= amount;
    }

    function donate(uint256 amount) external {
        amount = bound(amount, 0, MAX_AMOUNT / 10);
        asset.mint(address(vault), amount);
        ghostNav += amount;
    }

    /// @notice Sets a strategy's recall frictions. Haircuts run past the shortfall tolerance so the rebalance
    ///         guard is exercised in both directions.
    function setFrictions(uint256 strategySeed, uint256 haircut, uint256 liquidity) external {
        InvStrategy s = _registered(strategySeed);
        if (address(s) == address(0)) return;
        haircut = bound(haircut, 0, 2 * REBALANCE_SHORTFALL_TOLERANCE);
        liquidity = liquidity % 3 == 0 ? type(uint256).max : bound(liquidity, 0, MAX_AMOUNT);
        s.setFrictions(haircut, liquidity);
    }

    // ---- Manager ----

    /// @notice Permissionless rebalance. Predicts pass 1's recalls from the views: if any recall would lose more
    ///         than the tolerance the whole call must revert; otherwise the NAV drops by exactly the recall
    ///         haircuts, each at most the tolerance.
    function rebalance() external {
        uint256 navBefore = vault.totalAssets();
        address[] memory s = mgr.getStrategies();
        uint256 expectedLoss;
        bool shortfall;
        for (uint256 i; i < s.length; ++i) {
            uint256 current = InvStrategy(s[i]).totalAssetsManaged();
            uint256 target = navBefore * mgr.getStrategyTarget(s[i]) / 10_000;
            if (current > target) {
                (, uint256 lost) = InvStrategy(s[i]).quote(current - target);
                if (lost > REBALANCE_SHORTFALL_TOLERANCE) shortfall = true;
                expectedLoss += lost;
            }
        }

        if (shortfall) {
            vm.expectPartialRevert(IStrategyManager.StrategyManagerWithdrawShortfall.selector);
            mgr.rebalance();
            return;
        }

        mgr.rebalance();
        assertEq(vault.totalAssets(), navBefore - expectedLoss, "rebalance moved NAV beyond its haircuts");
        ghostNav -= expectedLoss;
    }

    /// @notice Retargets a registered strategy within the room left under 100%. One call in four asks for more
    ///         than that room and must be refused with the over-allocated total.
    function updateTarget(uint256 strategySeed, uint256 bps) external {
        InvStrategy s = _registered(strategySeed);
        if (address(s) == address(0)) return;
        uint256 others = mgr.totalTargetBps() - mgr.getStrategyTarget(address(s));
        uint256 room = 10_000 - others;
        if ((strategySeed / 8) % 4 == 0) {
            bps = bound(bps, room + 1, room + 10_000);
            vm.expectRevert(
                abi.encodeWithSelector(IStrategyManager.StrategyManagerInvalidAllocation.selector, others + bps)
            );
            vm.prank(mgrAdmin);
            mgr.updateStrategyTarget(address(s), uint16(bps));
            return;
        }
        vm.prank(mgrAdmin);
        mgr.updateStrategyTarget(address(s), uint16(bound(bps, 0, room)));
    }

    /// @notice Registers a strategy. `seed % 4` picks the case:
    ///         - 0: re-add a removed strategy. One still holding stranded funds is unbricked (funds kept) and
    ///           must be refused with {StrategyManagerStrategyNotEmpty}, since re-adding it would step the NAV up
    ///           (#270); one that holds nothing (returned, or removed empty) rejoins.
    ///         - 1: a fresh strategy asking for more than the room left under 100%, which must be refused with
    ///           the over-allocated total.
    ///         - otherwise: a fresh strategy within the room.
    function addStrategy(uint256 seed, uint256 bps) external {
        if (mgr.getStrategies().length >= MAX_REGISTERED) return;
        uint256 total = mgr.totalTargetBps();
        uint256 room = 10_000 - total;

        if (seed % 4 == 0) {
            InvStrategy s = _removed(seed / 4);
            if (address(s) == address(0)) return;
            s.unbrick();
            uint256 balance = asset.balanceOf(address(s));
            if (balance > 0) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IStrategyManager.StrategyManagerStrategyNotEmpty.selector, address(s), balance
                    )
                );
            }
            vm.prank(mgrAdmin);
            mgr.addStrategy(address(s), uint16(bound(bps, 0, room)));
            if (balance == 0) stranded[address(s)] = false;
            return;
        }

        if (seed % 4 == 1) {
            InvStrategy fresh = new InvStrategy(asset);
            bps = bound(bps, room + 1, room + 10_000);
            vm.expectRevert(
                abi.encodeWithSelector(IStrategyManager.StrategyManagerInvalidAllocation.selector, total + bps)
            );
            vm.prank(mgrAdmin);
            mgr.addStrategy(address(fresh), uint16(bps));
            return;
        }

        _newStrategy(uint16(bound(bps, 0, room)));
    }

    /// @notice Removes a strategy: an empty one is removed, one still holding funds must be refused.
    function removeStrategy(uint256 strategySeed) external {
        InvStrategy s = _registered(strategySeed);
        if (address(s) == address(0)) return;
        uint256 balance = s.totalAssetsManaged();
        if (balance > 0) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IStrategyManager.StrategyManagerStrategyStillAllocated.selector, address(s), balance
                )
            );
        }
        vm.prank(mgrAdmin);
        mgr.removeStrategy(address(s));
    }

    /// @notice Bricks a strategy's NAV read and force-removes it in one step: its funds leave the NAV and the
    ///         manager latches deposits. Runs on one call in four, so the latch is open most of the time and the
    ///         entry paths are exercised past their refusal.
    function forceRemove(uint256 strategySeed) external {
        if (strategySeed % 4 != 0) return;
        InvStrategy s = _registered(strategySeed / 4);
        if (address(s) == address(0)) return;
        uint256 balance = s.totalAssetsManaged();
        s.brick();
        vm.prank(mgrAdmin);
        mgr.removeStrategy(address(s));
        stranded[address(s)] = true;
        ghostLatched = true;
        ghostNav -= balance;
    }

    /// @notice A force-removed strategy pushes its stranded funds back to the vault, by plain transfer.
    function returnStranded(uint256 strategySeed) external {
        uint256 n = allStrategies.length;
        for (uint256 i; i < n; ++i) {
            InvStrategy s = allStrategies[(strategySeed % n + i) % n];
            if (!stranded[address(s)]) continue;
            stranded[address(s)] = false;
            ghostNav += asset.balanceOf(address(s));
            s.returnAll(address(vault));
            return;
        }
    }

    /// @notice Clears the latch. Odd seeds call from an actor and must be refused; clearing an unset latch reverts.
    function clearDepositLatch(uint256 callerSeed) external {
        if (callerSeed % 2 == 1) {
            address caller = _actor(callerSeed);
            vm.expectRevert(
                abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, bytes32(0))
            );
            vm.prank(caller);
            mgr.clearDepositLatch();
            return;
        }
        if (!ghostLatched) vm.expectRevert(IStrategyManagerRecovery.StrategyManagerDepositLatchNotSet.selector);
        vm.prank(mgrAdmin);
        mgr.clearDepositLatch();
        ghostLatched = false;
    }

    /// @notice The vault admin swaps to the next fresh manager (#305). The old manager's registered strategies
    ///         leave the NAV with their funds, stranded until they return. The swap must latch the vault exactly
    ///         when the old manager was latched or still reported allocations; the latch then outlives the swap
    ///         and the fresh manager starts unlatched. On even seeds the manager admin first clears the old
    ///         manager's latch, so a swap away from an unlatched manager holding nothing (a clean rotation) happens
    ///         too.
    function swapManager(uint256 seed) external {
        if (swaps >= _spareManagers.length) return;
        StrategyManager old = mgr;
        StrategyManager next = _spareManagers[swaps++];

        address[] memory s = old.getStrategies();
        uint256 allocated;
        for (uint256 i; i < s.length; ++i) {
            uint256 balance = InvStrategy(s[i]).totalAssetsManaged();
            allocated += balance;
            if (balance > 0) stranded[s[i]] = true;
        }
        uint256 navBefore = vault.totalAssets();
        bool expectLatch = (seed % 2 == 0 ? false : ghostLatched) || allocated > 0;
        if (seed % 2 == 0 && ghostLatched) {
            vm.prank(mgrAdmin);
            old.clearDepositLatch();
        }

        vm.prank(vaultAdmin);
        vault.setStrategyManager(address(next));
        mgr = next;

        assertEq(vault.totalAssets(), navBefore - allocated, "swap moved NAV beyond the stranded funds");
        ghostNav -= allocated;
        ghostLatched = false;
        ghostVaultLatched = ghostVaultLatched || expectLatch;
        assertEq(IVaultCoreRecovery(address(vault)).managerSwapLatched(), ghostVaultLatched, "swap latch vs ghost");
    }

    /// @notice Clears the vault's manager-swap latch. Odd seeds call from an actor and must be refused; clearing an
    ///         unset latch reverts.
    function clearManagerSwapLatch(uint256 callerSeed) external {
        if (callerSeed % 2 == 1) {
            address caller = _actor(callerSeed);
            vm.expectRevert(
                abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, bytes32(0))
            );
            vm.prank(caller);
            IVaultCoreRecovery(address(vault)).clearManagerSwapLatch();
            return;
        }
        if (!ghostVaultLatched) vm.expectRevert(IVaultCoreRecovery.VaultCoreManagerSwapLatchNotSet.selector);
        vm.prank(vaultAdmin);
        IVaultCoreRecovery(address(vault)).clearManagerSwapLatch();
        ghostVaultLatched = false;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               INVARIANT BASE
//////////////////////////////////////////////////////////////////////////*//

/// @title VaultDiamondInvariantBase
/// @notice Stateful properties of a recipe-built vault diamond wired to a recipe-built {DeployStrategyManager}
///         diamond and live strategies (#231 Phase 2):
///         - the NAV is idle plus what the registered strategies report, and matches an independent ghost NAV;
///         - assets are conserved across the vault, the strategies (registered or stranded), actors and losses;
///         - shares are conserved and never worth more than the NAV (no free shares);
///         - exits are capped at idle liquidity;
///         - the manager's deposit latch (#300) is set only by a force removal and cleared only by the manager
///           admin; the vault's manager-swap latch (#305) is set by exactly the swaps that may strand funds and
///           cleared only by the vault admin; while either is set, `maxDeposit`/`maxMint` are closed;
///         - targets stay within 100%, and over-allocations, re-adding a still-funded stranded strategy and a
///           rebalance recall losing more than the shortfall tolerance are refused (asserted in the handler).
abstract contract VaultDiamondInvariantBase is StrategyManagerTestBase {
    InvVaultAsset internal asset;
    IVaultCore internal vault;
    VaultHandler internal handler;

    address internal constant MGR_ADMIN = address(0xAD);
    uint256 internal constant SPARE_MANAGERS = 3;

    /// @dev Deploys the vault diamond over `asset_` through its recipe.
    function _deployVaultDiamond(address asset_) internal virtual returns (address);

    /// @dev The account holding the vault's DEFAULT_ADMIN_ROLE.
    function _vaultAdmin() internal view virtual returns (address);

    /// @dev Deploys a recipe-built manager administered by MGR_ADMIN and points it at the vault.
    function _newManager() internal returns (StrategyManager m) {
        m = StrategyManager(_deployStrategyManager(MGR_ADMIN));
        vm.prank(MGR_ADMIN);
        m.setVault(address(vault));
    }

    function setUp() public virtual {
        vm.warp(1_000_000);
        asset = new InvVaultAsset();
        vault = IVaultCore(_deployVaultDiamond(address(asset)));

        mgr = _newManager();
        diamond = address(mgr);
        vm.prank(_vaultAdmin());
        vault.setStrategyManager(diamond);

        StrategyManager[] memory spares = new StrategyManager[](SPARE_MANAGERS);
        for (uint256 i; i < SPARE_MANAGERS; ++i) {
            spares[i] = _newManager();
        }
        handler = new VaultHandler(vault, mgr, asset, MGR_ADMIN, _vaultAdmin(), spares);
        handler.addInitialStrategy(4_000);
        handler.addInitialStrategy(3_000);

        bytes4[] memory selectors = new bytes4[](19);
        selectors[0] = VaultHandler.deposit.selector;
        selectors[1] = VaultHandler.mint.selector;
        selectors[2] = VaultHandler.withdraw.selector;
        selectors[3] = VaultHandler.redeem.selector;
        selectors[4] = VaultHandler.transferShares.selector;
        selectors[5] = VaultHandler.strategyYield.selector;
        selectors[6] = VaultHandler.strategyLoss.selector;
        selectors[7] = VaultHandler.donate.selector;
        selectors[8] = VaultHandler.setFrictions.selector;
        selectors[9] = VaultHandler.rebalance.selector;
        selectors[10] = VaultHandler.updateTarget.selector;
        selectors[11] = VaultHandler.addStrategy.selector;
        selectors[12] = VaultHandler.removeStrategy.selector;
        selectors[13] = VaultHandler.forceRemove.selector;
        selectors[14] = VaultHandler.returnStranded.selector;
        selectors[15] = VaultHandler.clearDepositLatch.selector;
        // Weighted twice so the latch is set a minority of the time and entries mostly take the value path.
        selectors[16] = VaultHandler.clearDepositLatch.selector;
        selectors[17] = VaultHandler.swapManager.selector;
        selectors[18] = VaultHandler.clearManagerSwapLatch.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice `totalAssets` = idle + Σ registered strategies' reports = idle + `allocatedAssets`, and equals the
    ///         ghost NAV built from each action's expected effect.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_NavIsIdlePlusAllocated() public view {
        uint256 idle = vault.idleAssets();
        address[] memory s = handler.mgr().getStrategies();
        uint256 allocated;
        for (uint256 i; i < s.length; ++i) {
            allocated += IStrategy(s[i]).totalAssetsManaged();
        }
        uint256 nav = vault.totalAssets();
        assertEq(idle, asset.balanceOf(address(vault)), "idle != asset balance");
        assertEq(nav, idle + allocated, "totalAssets != idle + strategy reports");
        assertEq(vault.allocatedAssets(), allocated, "allocatedAssets != strategy reports");
        assertEq(nav, handler.ghostNav(), "totalAssets != ghost NAV");
    }

    /// @notice Every asset ever minted sits in the vault, a strategy (registered or stranded), an actor, or the
    ///         loss sink: nothing leaks, nothing appears.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_AssetConservation() public view {
        uint256 held = asset.balanceOf(address(vault)) + asset.balanceOf(address(0xDEAD));
        uint256 n = handler.strategyCount();
        for (uint256 i; i < n; ++i) {
            held += asset.balanceOf(address(handler.allStrategies(i)));
        }
        address[3] memory a = handler.actors();
        for (uint256 i; i < a.length; ++i) {
            held += asset.balanceOf(a[i]);
        }
        assertEq(held, asset.totalSupply(), "asset leaked or appeared");
    }

    /// @notice Shares are conserved (minted − burned = supply = Σ holders), and neither all shares nor the sum of
    ///         each holder's claim is worth more than the NAV.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SharesConservedNoFreeShares() public view {
        uint256 supply = vault.totalSupply();
        assertEq(supply, handler.ghostSharesMinted() - handler.ghostSharesBurned(), "supply != minted - burned");
        address[3] memory a = handler.actors();
        uint256 sum;
        uint256 claims;
        for (uint256 i; i < a.length; ++i) {
            uint256 bal = vault.balanceOf(a[i]);
            sum += bal;
            claims += vault.convertToAssets(bal);
        }
        uint256 nav = vault.totalAssets();
        assertEq(sum, supply, "supply != sum of holders");
        assertLe(claims, nav, "holders' claims exceed NAV");
        assertLe(vault.convertToAssets(supply), nav, "supply worth more than NAV");
    }

    /// @notice No holder is ever offered more than idle liquidity, or more than their shares are worth.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ExitsCappedAtIdle() public view {
        uint256 idle = vault.idleAssets();
        address[3] memory a = handler.actors();
        for (uint256 i; i < a.length; ++i) {
            uint256 maxAssets = vault.maxWithdraw(a[i]);
            assertLe(maxAssets, idle, "maxWithdraw > idle");
            assertLe(maxAssets, vault.convertToAssets(vault.balanceOf(a[i])), "maxWithdraw > claim");
            assertLe(vault.previewRedeem(vault.maxRedeem(a[i])), idle, "previewRedeem(maxRedeem) > idle");
            assertLe(vault.maxRedeem(a[i]), vault.balanceOf(a[i]), "maxRedeem > balance");
        }
    }

    /// @notice Both latches match their ghosts: the configured manager's (set only by a force removal, cleared only
    ///         by the manager admin) and the vault's manager-swap latch (set only by a swap that may strand funds,
    ///         cleared only by the vault admin). While either is set, entries report 0, otherwise they are
    ///         unbounded. `totalTargetBps` is the sum of the targets and stays within 100% (the handler also asks
    ///         for over-allocations and asserts they are refused). The rebalance loss bound is enforced inside the
    ///         handler: a rebalance either moves the NAV by exactly the predicted recall haircuts, each within the
    ///         shortfall tolerance, or reverts with the shortfall.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_LatchAndRebalanceBounds() public view {
        StrategyManager m = handler.mgr();
        bool latched = handler.ghostLatched();
        bool vaultLatched = handler.ghostVaultLatched();
        assertEq(m.depositsLatched(), latched, "manager latch diverged from ghost");
        assertEq(
            IVaultCoreRecovery(address(vault)).managerSwapLatched(), vaultLatched, "swap latch diverged from ghost"
        );
        address[3] memory a = handler.actors();
        uint256 open = latched || vaultLatched ? 0 : type(uint256).max;
        for (uint256 i; i < a.length; ++i) {
            assertEq(vault.maxDeposit(a[i]), open, "maxDeposit vs latch");
            assertEq(vault.maxMint(a[i]), open, "maxMint vs latch");
        }

        address[] memory s = m.getStrategies();
        uint256 bps;
        for (uint256 i; i < s.length; ++i) {
            bps += m.getStrategyTarget(s[i]);
        }
        assertEq(m.totalTargetBps(), bps, "totalTargetBps != sum of targets");
        assertLe(bps, 10_000, "targets exceed 100%");
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                          RECIPE-DIAMOND SUITES
//////////////////////////////////////////////////////////////////////////*//

/// @title VaultCoreDiamondInvariant
/// @notice The vault properties on a {DeployVaultCore} diamond.
/// forge-config: ci.invariant.runs = 64
contract VaultCoreDiamondInvariant is VaultDiamondInvariantBase {
    address internal constant VAULT_ADMIN = address(0xADAD);

    function _deployVaultDiamond(address asset_) internal override returns (address) {
        DeployVaultCore recipe = new DeployVaultCore();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            recipe.buildCuts(asset_, "Vault Share", "vSHARE", VAULT_ADMIN, 0);
        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        return address(d);
    }

    function _vaultAdmin() internal pure override returns (address) {
        return VAULT_ADMIN;
    }
}

/// @title GovernedVaultDiamondInvariant
/// @notice The vault properties on a {DeployGovernedVault} diamond, whose deposit/mint/withdraw/redeem are the
///         {GovernedVault} vote-checkpoint wrappers. Every actor self-delegates, so voting power must also track
///         the shares exactly.
/// forge-config: ci.invariant.runs = 64
contract GovernedVaultDiamondInvariant is VaultDiamondInvariantBase {
    function _deployVaultDiamond(address asset_) internal override returns (address v) {
        GovernedVaultParams memory p;
        p.asset = asset_;
        p.name = "Governed Vault Share";
        p.symbol = "gVLT";
        p.minDelay = 100;
        p.votingDelay = 1;
        p.votingPeriod = 50;
        p.quorumNumerator = 4;
        LatticeFactory factory = new LatticeFactory(new LatticeRegistry(address(this)), address(0), address(0));
        v = new DeployGovernedVault().deployAtomic(p, factory, bytes32(0));
    }

    /// @dev The diamond is its own DEFAULT_ADMIN_ROLE holder; a passed proposal makes the same calls.
    function _vaultAdmin() internal view override returns (address) {
        return address(vault);
    }

    function setUp() public override {
        super.setUp();
        address[3] memory a = handler.actors();
        for (uint256 i; i < a.length; ++i) {
            vm.prank(a[i]);
            IVotes(address(vault)).delegate(a[i]);
        }
    }

    /// @notice Each self-delegated holder's votes equal their shares, so the votes sum to the supply.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_VotesTrackShares() public view {
        address[3] memory a = handler.actors();
        uint256 votes;
        for (uint256 i; i < a.length; ++i) {
            uint256 v = IVotes(address(vault)).getVotes(a[i]);
            assertEq(v, vault.balanceOf(a[i]), "votes != shares");
            votes += v;
        }
        assertEq(votes, vault.totalSupply(), "votes != supply");
    }
}
