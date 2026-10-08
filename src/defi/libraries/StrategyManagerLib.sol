// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {IStrategyManager} from "@lattice/interfaces/defi/IStrategyManager.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IStrategy} from "@lattice/interfaces/external/yearn/IStrategy.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.StrategyManager")) - 1)) & ~bytes32(uint256(0xff))`.
/// Precomputed: 0x1b00913e47c53f1d64d326bde2ad6a7904ed791d4ee4432bc133be907894ca00
bytes32 constant STRATEGY_MANAGER_STORAGE_SLOT = 0x1b00913e47c53f1d64d326bde2ad6a7904ed791d4ee4432bc133be907894ca00;

/// @dev ERC-165 storage location (shared across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant STRATEGY_MANAGER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0xcce4011b is `type(IStrategyManager).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xcce4011b), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ISTRATEGYMANAGER_SLOT = 0x3d05027e9ebc1daac4235d8ac5fc59b9acea5ece08ff307b79ab5b69ad569930;

/// @dev Maximum number of strategies that can be registered simultaneously.
/// Limits the iteration cost of totalAllocated() (read by every ERC-4626 conversion, preview,
/// max* view and mutator via VaultCore.totalAssets()) and rebalance(), preventing gas-based DoS.
uint256 constant MAX_STRATEGIES = 20;

/// @dev Largest value loss, in the asset's smallest unit, that `rebalance()` accepts on one strategy recall: the
///      drop in the strategy's reported balance may exceed what the vault received by at most this much. Sized
///      for share/index rounding (a few wei); anything larger is a real loss and reverts with
///      {IStrategyManager.StrategyManagerWithdrawShortfall}. Fixed by design: not configurable, no storage.
uint256 constant REBALANCE_SHORTFALL_TOLERANCE = 10;

/// @dev `IERC165.supportsInterface(bytes4)`, probed before `rebalance()` calls an adapter's `deploy()`.
bytes4 constant ERC165_SUPPORTS_INTERFACE_SELECTOR = 0x01ffc9a7;

/// @notice Storage struct for StrategyManager module.
/// @custom:storage-location erc7201:lattice.storage.StrategyManager
struct StrategyManagerStorage {
    address _vault;
    address[] _strategies;
    mapping(address strategy => uint16 targetBps) _targets;
    /// @dev 1-based index into `_strategies` array. 0 means not registered.
    mapping(address strategy => uint256 strategyIndex) _strategyIndex;
    uint256 _totalTargetBps;
}

/// @title StrategyManagerLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Yearn V3 (https://github.com/yearn/yearn-vaults-v3/blob/master/contracts/VaultV3.vy)
/// @notice Library implementing yield strategy management for a single ERC-4626 vault.
/// @dev All logic lives here; the StrategyManager facet is a pure delegator.
///
///      Architecture:
///      - The StrategyManager holds a registry of trusted external strategies and their
///        target allocations (in basis points, sum <= 10 000).
///      - `totalAllocated()` sums each strategy's self-reported balance
///        (trust assumption: strategies report accurate values).
///      - `harvest()` is a public snapshotting function that emits the current total
///        for off-chain indexers without moving any funds.
///      - `rebalance()` drives assets to/from strategies to match target allocations.
///        It calls `IVaultCore.allocateToStrategy` (vault pushes excess) and
///        `IStrategy.withdraw` (strategy pushes back to vault) as needed, then
///        `IProtocolAdapter.deploy` so an adapter's idle does not stay undeployed.
library StrategyManagerLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function strategyManagerStorage() internal pure returns (StrategyManagerStorage storage $) {
        assembly {
            $.slot := STRATEGY_MANAGER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the StrategyManager module.
    /// @dev Must be called inside a pre/postInitializer block.
    ///      AccessControl must already be initialized.
    function __StrategyManager_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IStrategyManager interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ISTRATEGYMANAGER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the address of the associated vault.
    function vault() internal view returns (address) {
        return strategyManagerStorage()._vault;
    }

    /// @notice Returns all registered strategy addresses.
    function getStrategies() internal view returns (address[] memory) {
        return strategyManagerStorage()._strategies;
    }

    /// @notice Returns the target allocation in bps for a strategy (0 if not registered).
    function getStrategyTarget(address strategy) internal view returns (uint16) {
        return strategyManagerStorage()._targets[strategy];
    }

    /// @notice Returns the current sum of all target allocations in basis points.
    function totalTargetBps() internal view returns (uint256) {
        return strategyManagerStorage()._totalTargetBps;
    }

    /// @notice Returns the sum of all strategies' self-reported managed balances.
    /// @dev Trust assumption: each registered strategy must accurately report
    ///      `totalAssetsManaged()`. A malicious strategy could inflate this value,
    ///      causing the vault to miscalculate share prices. Only add audited strategies.
    ///      Reverts if any strategy's read reverts (or the sum overflows); the vault then fails closed until
    ///      the admin force-removes a reverting strategy through `removeStrategy`, or, as a last resort, the
    ///      vault admin points `VaultCore.setStrategyManager` at a fresh manager.
    function totalAllocated() internal view returns (uint256 total) {
        StrategyManagerStorage storage $ = strategyManagerStorage();
        uint256 len = $._strategies.length;
        for (uint256 i; i < len; ++i) {
            total += IStrategy($._strategies[i]).totalAssetsManaged();
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets the vault address. Admin-only (DEFAULT_ADMIN_ROLE).
    /// @param _vault Address of the ERC-4626 vault this manager serves.
    function setVault(address _vault) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setVault(_vault);
    }

    /// @dev Inner logic for setVault (no auth check).
    function _setVault(address _vault) internal {
        if (_vault == address(0)) revert IStrategyManager.StrategyManagerVaultNotSet();
        strategyManagerStorage()._vault = _vault;
        emit IStrategyManager.VaultSet(_vault);
    }

    /// @notice Registers a new strategy with a target allocation. Admin-only.
    /// @dev Reverts with {IStrategyManager.StrategyManagerStrategyNotEmpty} if the strategy already reports a
    ///      balance, and bubbles the revert if its `totalAssetsManaged()` read fails.
    /// @param strategy Strategy contract address.
    /// @param targetBps Target allocation in basis points (0–10 000).
    function addStrategy(address strategy, uint16 targetBps) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _addStrategy(strategy, targetBps);
    }

    /// @dev Inner logic for addStrategy.
    function _addStrategy(address strategy, uint16 targetBps) internal {
        StrategyManagerStorage storage $ = strategyManagerStorage();

        if (strategy == address(0)) revert IStrategyManager.StrategyManagerInvalidStrategy(strategy);
        if ($._strategyIndex[strategy] != 0) revert IStrategyManager.StrategyManagerStrategyAlreadyAdded(strategy);
        if ($._strategies.length >= MAX_STRATEGIES) revert IStrategyManager.StrategyManagerTooManyStrategies();

        // Verify asset compatibility.
        address vaultAddr = $._vault;
        if (vaultAddr != address(0)) {
            address vaultAsset = IERC4626(vaultAddr).asset();
            address strategyAsset = IStrategy(strategy).asset();
            if (strategyAsset != vaultAsset) revert IStrategyManager.StrategyManagerAssetMismatch(strategy);
        }

        // A new strategy must start empty: a reported balance would step the vault's NAV up on add, handing
        // that value to whoever holds shares now (e.g. re-adding a force-removed strategy that still holds
        // the stranded funds). A reverting read bubbles: such a strategy would freeze the vault on the spot.
        uint256 balance = IStrategy(strategy).totalAssetsManaged();
        if (balance > 0) revert IStrategyManager.StrategyManagerStrategyNotEmpty(strategy, balance);

        // Validate total allocation would not exceed 100%.
        uint256 newTotal = $._totalTargetBps + targetBps;
        if (newTotal > 10_000) revert IStrategyManager.StrategyManagerInvalidAllocation(newTotal);

        $._strategies.push(strategy);
        $._strategyIndex[strategy] = $._strategies.length; // 1-based
        $._targets[strategy] = targetBps;
        $._totalTargetBps = newTotal;

        emit IStrategyManager.StrategyAdded(strategy, targetBps);
    }

    /// @notice Removes a registered strategy. Admin-only. Uses swap-and-pop.
    /// @dev A strategy whose `totalAssetsManaged()` read fails is force-removed (see {_removeStrategy}).
    /// @param strategy Strategy address to remove.
    function removeStrategy(address strategy) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _removeStrategy(strategy);
    }

    /// @dev Inner logic for removeStrategy.
    ///      Force removal: a failing balance read makes {totalAllocated} revert, which makes the vault's
    ///      `totalAssets()` revert and freezes the vault (fail closed). To recover, a strategy whose read
    ///      reverts or returns malformed data is removed without the balance check and emits
    ///      {IStrategyManager.StrategyForceRemoved}. Any funds it still holds leave the vault's NAV and
    ///      deposits reopen at the lower NAV. Funds it later returns to the vault, by any path, accrue to
    ///      whoever holds shares at that moment, including depositors who entered after the removal, so a
    ///      recovery moves value from pre-removal holders to them. {_addStrategy} rejects re-adding it while
    ///      it still reports a balance.
    ///      A strategy that reports a well-formed but overflowing balance also freezes the vault, yet is not
    ///      a failed read here and cannot be force-removed; the last resort is `VaultCore.setStrategyManager`
    ///      with a fresh manager, which drops all of this manager's strategies from the NAV.
    function _removeStrategy(address strategy) internal {
        StrategyManagerStorage storage $ = strategyManagerStorage();

        uint256 idx = $._strategyIndex[strategy];
        if (idx == 0) revert IStrategyManager.StrategyManagerStrategyNotFound(strategy);

        // Guard against removing a strategy that still holds vault assets (M-3).
        // Removing a live strategy silently removes those assets from totalAllocated()
        // accounting, immediately dropping the share price and stranding the capital.
        // Operators must rebalance (or set targetBps to 0 and rebalance) to recall
        // funds before removing a strategy. A low-level staticcall (rather than try/catch,
        // which cannot catch a return-data decode failure) treats a reverting or undecodable
        // read as failed. An overflowing sum in {totalAllocated} is not caught here.
        (bool ok, bytes memory data) =
            strategy.staticcall(abi.encodeWithSelector(IStrategy.totalAssetsManaged.selector));
        if (ok && data.length >= 32) {
            uint256 liveBalance = abi.decode(data, (uint256));
            if (liveBalance > 0) {
                revert IStrategyManager.StrategyManagerStrategyStillAllocated(strategy, liveBalance);
            }
        } else {
            emit IStrategyManager.StrategyForceRemoved(strategy);
        }

        uint256 arrIdx = idx - 1; // convert to 0-based
        uint256 lastIdx = $._strategies.length - 1;

        if (arrIdx != lastIdx) {
            // Swap with last element.
            address last = $._strategies[lastIdx];
            $._strategies[arrIdx] = last;
            $._strategyIndex[last] = idx; // update swapped element's index
        }

        $._strategies.pop();
        delete $._strategyIndex[strategy];

        $._totalTargetBps -= $._targets[strategy];
        delete $._targets[strategy];

        emit IStrategyManager.StrategyRemoved(strategy);
    }

    /// @notice Updates the target allocation for a registered strategy. Admin-only.
    /// @param strategy Registered strategy address.
    /// @param newBps New target allocation in basis points.
    function updateStrategyTarget(address strategy, uint16 newBps) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _updateStrategyTarget(strategy, newBps);
    }

    /// @dev Inner logic for updateStrategyTarget.
    function _updateStrategyTarget(address strategy, uint16 newBps) internal {
        StrategyManagerStorage storage $ = strategyManagerStorage();

        if ($._strategyIndex[strategy] == 0) revert IStrategyManager.StrategyManagerStrategyNotFound(strategy);

        uint16 oldBps = $._targets[strategy];
        uint256 newTotal = $._totalTargetBps - oldBps + newBps;
        if (newTotal > 10_000) revert IStrategyManager.StrategyManagerInvalidAllocation(newTotal);

        $._targets[strategy] = newBps;
        $._totalTargetBps = newTotal;

        emit IStrategyManager.StrategyTargetUpdated(strategy, oldBps, newBps);
    }

    /// @notice Snapshots the current allocated balance across all strategies and emits Harvested.
    /// @dev Anyone can call; no funds move. Useful for off-chain indexers tracking yield accrual.
    function harvest() internal {
        uint256 total = totalAllocated();
        emit IStrategyManager.Harvested(total);
    }

    /// @notice Rebalances the vault's asset distribution to match strategy target allocations.
    /// @dev Uses a two-pass approach to avoid order-dependent atomicity failures (M-1):
    ///      Pass 1 — process all over-allocated strategies (withdrawals back to vault) first.
    ///      Pass 2 — process all under-allocated strategies (allocations from vault) second.
    ///      This guarantees the vault holds maximum idle balance before any allocation is
    ///      attempted, regardless of strategy registration order. A final pass then deploys each
    ///      protocol adapter's idle (#221).
    ///
    ///      For each strategy in pass 1:
    ///      - If current > target: calls IStrategy.withdraw and checks the recall (see {_recall}).
    ///      For each strategy in pass 2:
    ///      - If current < target: calls IVaultCore.allocateToStrategy, capped at the vault's actual idle.
    ///      For each strategy in the deploy pass:
    ///      - If it holds idle asset and advertises IProtocolAdapter: calls its `deploy()` (see {_deployIdle}).
    ///
    ///      Anyone can call. Protected against reentrancy (M-2): the guard is held for the whole
    ///      rebalance, and VaultCore rejects deposit/mint/withdraw/redeem while it is held
    ///      (`reentrancyGuardEntered()`), closing the read-only-reentrancy window.
    ///
    ///      `vaultTotal` is read once and intentionally includes the vault's idle balance (a raw
    ///      ERC-20 balance). A direct token donation to the vault therefore raises every target —
    ///      this is correct: a donation is NAV that belongs to share holders and is simply deployed
    ///      per the configured allocation. Funds only move to pre-vetted strategies (trust model:
    ///      add audited strategies only), and share-price manipulation from donations is bounded by
    ///      ERC-4626's virtual-shares offset. AUM is conserved across idle<->strategy moves (pass 1
    ///      rejects any recall that loses more than {REBALANCE_SHORTFALL_TOLERANCE}), so the single
    ///      `vaultTotal` snapshot stays valid for sizing targets. An honest partial recall leaves the
    ///      vault with less idle than the snapshot implies, so pass 2 allocates from the idle it
    ///      actually holds and, when that runs out, later strategies in registration order wait for the
    ///      next rebalance.
    function rebalance() internal {
        ReentrancyGuardLib.nonReentrantBefore();
        _rebalance();
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @dev Inner rebalance logic (called after reentrancy lock is acquired).
    function _rebalance() private {
        StrategyManagerStorage storage $ = strategyManagerStorage();
        address vaultAddr = $._vault;
        if (vaultAddr == address(0)) revert IStrategyManager.StrategyManagerVaultNotSet();

        address asset_ = IERC4626(vaultAddr).asset();
        uint256 vaultTotal = IERC4626(vaultAddr).totalAssets();
        uint256 len = $._strategies.length;

        // Pass 1: withdraw excess from over-allocated strategies. Bit i of `recalled` marks strategy i
        // (len <= MAX_STRATEGIES) so pass 2 does not hand a recall's rounding remainder straight back.
        uint256 recalled;
        for (uint256 i; i < len; ++i) {
            address strategy = $._strategies[i];
            uint256 current = IStrategy(strategy).totalAssetsManaged();
            uint256 target = (vaultTotal * $._targets[strategy]) / 10_000;

            if (current > target) {
                _recall(strategy, current, current - target, vaultAddr, asset_);
                recalled |= 1 << i;
            }
        }

        // Pass 2: allocate deficit to under-allocated strategies, from the idle the vault actually holds.
        uint256 idle = IERC20(asset_).balanceOf(vaultAddr);
        for (uint256 i; i < len && idle > 0; ++i) {
            if (recalled & (1 << i) != 0) continue;
            address strategy = $._strategies[i];
            uint256 current = IStrategy(strategy).totalAssetsManaged();
            uint256 target = (vaultTotal * $._targets[strategy]) / 10_000;

            if (current < target) {
                uint256 amount = target - current;
                if (amount > idle) amount = idle;
                IVaultCore(vaultAddr).allocateToStrategy(strategy, amount);
                idle -= amount;
            }
        }

        // Deploy pass: put each protocol adapter's idle to work.
        for (uint256 i; i < len; ++i) {
            _deployIdle($._strategies[i], asset_);
        }

        emit IStrategyManager.Rebalanced();
    }

    /// @dev Recalls `requested` from `strategy` (which reported `current`) and checks it by value, not by the
    ///      amount asked (H-3, #221). `received` is the vault's actual idle delta and `released` the drop in
    ///      the strategy's reported balance. Reverts with {IStrategyManager.StrategyManagerWithdrawShortfall}
    ///      when `released` exceeds `received` by more than {REBALANCE_SHORTFALL_TOLERANCE}: the recall lost
    ///      value (slippage, an exit fee, or a strategy writing off more than it paid), which a permissionless
    ///      caller must not be able to realize. A recall that delivers less than asked while the strategy
    ///      still reports the remainder (the Lido buffer, a UniswapV3 rounding remainder) is an honest partial
    ///      recall: it completes, emits {IStrategyManager.StrategyPartiallyRecalled}, and the strategy stays
    ///      over target until a later rebalance.
    function _recall(address strategy, uint256 current, uint256 requested, address vaultAddr, address asset_) private {
        uint256 idleBefore = IERC20(asset_).balanceOf(vaultAddr);
        IStrategy(strategy).withdraw(requested, vaultAddr);
        uint256 received = IERC20(asset_).balanceOf(vaultAddr) - idleBefore;
        uint256 remaining = IStrategy(strategy).totalAssetsManaged();
        uint256 released = current > remaining ? current - remaining : 0;
        if (released > received + REBALANCE_SHORTFALL_TOLERANCE) {
            revert IStrategyManager.StrategyManagerWithdrawShortfall(strategy, released, received);
        }
        if (received + REBALANCE_SHORTFALL_TOLERANCE < requested) {
            emit IStrategyManager.StrategyPartiallyRecalled(strategy, requested, received);
        }
    }

    /// @dev Calls `deploy()` on `strategy` when it holds idle `asset_` and advertises
    ///      {IProtocolAdapter} through ERC-165, so allocations do not sit idle in the adapter (#221; the
    ///      adapters only accept `deploy` from their operator, this manager). Plain {IStrategy}s are skipped.
    ///      A reverting deploy (paused adapter or protocol, a supply cap, an operator not yet wired) is caught
    ///      and reported with {IStrategyManager.StrategyDeployFailed}: the idle stays in the adapter, counted
    ///      in its NAV, and never blocks the rebalance.
    function _deployIdle(address strategy, address asset_) private {
        if (IERC20(asset_).balanceOf(strategy) == 0) return;
        (bool ok, bytes memory ret) = strategy.staticcall(
            abi.encodeWithSelector(ERC165_SUPPORTS_INTERFACE_SELECTOR, type(IProtocolAdapter).interfaceId)
        );
        if (!ok || ret.length < 32 || abi.decode(ret, (uint256)) != 1) return;
        (ok, ret) = strategy.call(abi.encodeWithSelector(IProtocolAdapter.deploy.selector));
        if (!ok) emit IStrategyManager.StrategyDeployFailed(strategy, ret);
    }
}
