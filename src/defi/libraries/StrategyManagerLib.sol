// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IERC4626} from "@lattice/interfaces/IERC4626.sol";
import {IStrategyManager} from "@lattice/interfaces/IStrategyManager.sol";
import {IVaultCore} from "@lattice/interfaces/IVaultCore.sol";
import {IStrategy} from "@lattice/interfaces/external/IStrategy.sol";

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
///        `IStrategy.withdraw` (strategy pushes back to vault) as needed.
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
    function totalAllocated() internal view returns (uint256 total) {
        StrategyManagerStorage storage $ = strategyManagerStorage();
        uint256 len = $._strategies.length;
        for (uint256 i; i < len; i++) {
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

        // Verify asset compatibility.
        address vaultAddr = $._vault;
        if (vaultAddr != address(0)) {
            address vaultAsset = IERC4626(vaultAddr).asset();
            address strategyAsset = IStrategy(strategy).asset();
            if (strategyAsset != vaultAsset) revert IStrategyManager.StrategyManagerAssetMismatch(strategy);
        }

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
    /// @param strategy Strategy address to remove.
    function removeStrategy(address strategy) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _removeStrategy(strategy);
    }

    /// @dev Inner logic for removeStrategy.
    function _removeStrategy(address strategy) internal {
        StrategyManagerStorage storage $ = strategyManagerStorage();

        uint256 idx = $._strategyIndex[strategy];
        if (idx == 0) revert IStrategyManager.StrategyManagerStrategyNotFound(strategy);

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
    /// @dev For each strategy:
    ///      - If current > target: calls IStrategy.withdraw to push excess back to vault.
    ///      - If current < target: calls IVaultCore.allocateToStrategy to push deficit to strategy.
    ///      No-op if vault is not set. Anyone can call.
    function rebalance() internal {
        StrategyManagerStorage storage $ = strategyManagerStorage();
        address vaultAddr = $._vault;
        if (vaultAddr == address(0)) revert IStrategyManager.StrategyManagerVaultNotSet();

        uint256 vaultTotal = IERC4626(vaultAddr).totalAssets();
        uint256 len = $._strategies.length;

        for (uint256 i; i < len; i++) {
            address strategy = $._strategies[i];
            uint256 current = IStrategy(strategy).totalAssetsManaged();
            uint256 target = (vaultTotal * $._targets[strategy]) / 10_000;

            if (current > target) {
                // Strategy holds too much — withdraw excess back to vault.
                IStrategy(strategy).withdraw(current - target, vaultAddr);
            } else if (current < target) {
                // Vault has too little in strategy — allocate deficit.
                IVaultCore(vaultAddr).allocateToStrategy(strategy, target - current);
            }
        }

        emit IStrategyManager.Rebalanced();
    }
}
