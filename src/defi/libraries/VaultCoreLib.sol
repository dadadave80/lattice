// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IStrategyManager} from "@lattice/interfaces/defi/IStrategyManager.sol";
import {IStrategyManagerRecovery} from "@lattice/interfaces/defi/IStrategyManagerRecovery.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IVaultCoreRecovery} from "@lattice/interfaces/defi/IVaultCoreRecovery.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.VaultCore")) - 1)) & ~bytes32(uint256(0xff))`.
/// Precomputed: 0x391c4f0f82559e85ff01d307d4b19b40f088495abd453c84d7e0fa35497de600
bytes32 constant VAULT_CORE_STORAGE_SLOT = 0x391c4f0f82559e85ff01d307d4b19b40f088495abd453c84d7e0fa35497de600;

/// @dev ERC-165 storage location (shared across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant VAULT_CORE_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0xa86d8962 is `type(IVaultCore).interfaceId` (XOR of VaultCore-specific selectors; inherited IERC4626/IERC20 excluded).
/// `keccak256(abi.encode(bytes4(0xa86d8962), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IVAULTCORE_SLOT = 0xee1c77df59bab5696d7427515bb0fba56d8719259c4cc5bc6587a3654b26bdf2;

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.VaultCoreRecovery")) - 1)) & ~bytes32(uint256(0xff))`.
/// Precomputed: 0x47912b574bd5afb37a2207dcbb19ecd0a5ba9d0ace45a4775d2beed47d20cd00
bytes32 constant VAULT_CORE_RECOVERY_STORAGE_SLOT = 0x47912b574bd5afb37a2207dcbb19ecd0a5ba9d0ace45a4775d2beed47d20cd00;

/// @dev 0x065383d4 is `type(IVaultCoreRecovery).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x065383d4), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IVAULTCORERECOVERY_SLOT =
    0x5537f73b9d1f73b54596091975d6c567826a5e930691e592f6a854f19cdcd2fb;

/// @notice Storage struct for VaultCore module.
/// @custom:storage-location erc7201:lattice.storage.VaultCore
struct VaultCoreStorage {
    address _strategyManager;
}

/// @notice Vault-side deposit latch of the VaultCore module ({IVaultCoreRecovery}), kept in its own namespace
///         because {VaultCoreStorage} is live and frozen.
/// @custom:storage-location erc7201:lattice.storage.VaultCoreRecovery
struct VaultCoreRecoveryStorage {
    /// @dev Set by a strategy-manager swap that may strand funds, cleared by the vault admin (#305).
    bool _managerSwapLatched;
}

/// @title VaultCoreLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol)
/// @notice Library extending ERC-4626 vaults with strategy hooks for yield aggregation.
/// @dev All logic lives here; the VaultCore facet is a pure delegator. Storage is accessed
///      via ERC-7201 namespaced slot to avoid collisions in the Diamond proxy.
///
///      Architecture:
///      - The vault holds "idle" assets (its own ERC-20 balance of the underlying).
///      - When a StrategyManager is configured, it can direct the vault to PUSH assets to
///        external strategies via `allocateToStrategy`. The strategy later PUSHES back via
///        its own `withdraw` call.
///      - `totalAssets()` is overridden to include both idle and allocated assets. {ERC4626Lib} prices
///        shares by self-staticcalling the diamond's `totalAssets()`, so conversions, previews and
///        mutators all use this full NAV, while `maxWithdraw`/`maxRedeem` stay capped at idle assets.
///      - After a strategy force removal the manager latches deposits closed ({depositsLatched}): deposit/mint
///        revert and `maxDeposit`/`maxMint` return 0 until the manager admin clears the latch (#270).
///      - A strategy-manager swap that may strand funds (the old manager is latched, still reports allocations,
///        or cannot answer) latches deposits on the vault itself until the vault admin clears it (#305).
library VaultCoreLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function vaultCoreStorage() internal pure returns (VaultCoreStorage storage $) {
        assembly {
            $.slot := VAULT_CORE_STORAGE_SLOT
        }
    }

    function vaultCoreRecoveryStorage() internal pure returns (VaultCoreRecoveryStorage storage $) {
        assembly {
            $.slot := VAULT_CORE_RECOVERY_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the VaultCore module.
    /// @dev Must be called inside a pre/postInitializer block, after ERC4626Lib.__ERC4626_init.
    ///      AccessControl must already be initialized to support the DEFAULT_ADMIN_ROLE check.
    function __VaultCore_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterfaces();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IVaultCore and IVaultCoreRecovery interfaces via ERC-165.
    function registerInterfaces() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IVAULTCORE_SLOT, true)
            sstore(ERC165_MAP_IVAULTCORERECOVERY_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the configured strategy manager address, or address(0) if not set.
    function strategyManager() internal view returns (address) {
        return vaultCoreStorage()._strategyManager;
    }

    /// @notice Returns the vault's current idle asset balance.
    /// @dev Defined as the ERC-20 balance of the underlying asset held by this contract.
    function idleAssets() internal view returns (uint256) {
        return IERC20(ERC4626Lib.asset()).balanceOf(address(this));
    }

    /// @notice Returns the total assets held by the vault, including strategy allocations.
    /// @dev Backs the diamond's `totalAssets()` selector (replacing {ERC4626Lib.totalAssets}), which
    ///      {ERC4626Lib} reads for all share pricing. When a manager is set, adds the manager's
    ///      `totalAllocated()` view (which sums each strategy's self-reported balance).
    ///      Trust assumption: strategy balance reports are accurate.
    ///      Fails closed: if the manager read reverts or returns malformed data, this reverts with
    ///      {IVaultCore.VaultCoreStrategyNavUnavailable} rather than under-reporting the NAV as idle, which
    ///      would let deposits mint shares cheaply and exits redeem at a discount. `allocatedAssets()` reverts too.
    function totalAssets() internal view returns (uint256) {
        uint256 idle = idleAssets();
        address manager = vaultCoreStorage()._strategyManager;
        if (manager == address(0)) return idle;
        // IStrategyManager.totalAllocated() is the sum of IStrategy.totalAssetsManaged()
        // across all registered strategies.
        (bool ok, bytes memory data) = manager.staticcall(abi.encodeWithSignature("totalAllocated()"));
        if (!ok || data.length < 32) revert IVaultCore.VaultCoreStrategyNavUnavailable(manager);
        uint256 allocated = abi.decode(data, (uint256));
        return idle + allocated;
    }

    /// @notice Returns total assets allocated to strategies (totalAssets - idleAssets).
    function allocatedAssets() internal view returns (uint256) {
        uint256 total = totalAssets();
        uint256 idle = idleAssets();
        return total > idle ? total - idle : 0;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets the strategy manager address. Restricted to DEFAULT_ADMIN_ROLE.
    /// @dev Latches deposits on the vault when the swap may strand funds (see {_setStrategyManager}).
    /// @param manager The new strategy manager address.
    function setStrategyManager(address manager) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setStrategyManager(manager);
    }

    /// @dev Inner logic for setStrategyManager (no auth check — auth in outer).
    ///      Swapping away from a manager drops its strategies from the NAV and its own deposit latch with it, so
    ///      funds those strategies return later would move value to whoever deposited after the swap (#305).
    ///      Unless the previous manager verifiably releases cleanly ({_releasesCleanly}), the swap sets the
    ///      vault-side latch and emits {IVaultCoreRecovery.ManagerSwapLatchSet}. The reads never revert the swap:
    ///      it is the vault admin's last-resort recovery when the old manager's NAV read is broken. Setting the
    ///      first manager, or the same manager again, strands nothing and latches nothing.
    function _setStrategyManager(address manager) internal {
        if (manager == address(0)) revert IVaultCore.VaultCoreInvalidManager();
        VaultCoreStorage storage $ = vaultCoreStorage();
        address previous = $._strategyManager;
        if (previous != address(0) && previous != manager && !_releasesCleanly(previous)) {
            vaultCoreRecoveryStorage()._managerSwapLatched = true;
            emit IVaultCoreRecovery.ManagerSwapLatchSet(previous);
        }
        $._strategyManager = manager;
        emit IVaultCore.StrategyManagerSet(manager);
    }

    /// @notice Clears the manager-swap latch, reopening deposits unless the configured manager's own latch is set.
    ///         Restricted to DEFAULT_ADMIN_ROLE (the role that gates {setStrategyManager}).
    function clearManagerSwapLatch() internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _clearManagerSwapLatch();
    }

    /// @dev Inner logic for clearManagerSwapLatch (no auth check).
    function _clearManagerSwapLatch() internal {
        VaultCoreRecoveryStorage storage $ = vaultCoreRecoveryStorage();
        if (!$._managerSwapLatched) revert IVaultCoreRecovery.VaultCoreManagerSwapLatchNotSet();
        $._managerSwapLatched = false;
        emit IVaultCoreRecovery.ManagerSwapLatchCleared(msg.sender);
    }

    /// @notice Transfers idle assets to a strategy. Only callable by the strategy manager.
    /// @param strategy Destination strategy address.
    /// @param amount Amount of underlying asset to transfer.
    /// @dev Empty return data counts as success only when the asset has code (matches OpenZeppelin SafeERC20).
    function allocateToStrategy(address strategy, uint256 amount) internal {
        _checkManager();
        address asset = ERC4626Lib.asset();
        (bool ok, bytes memory ret) = asset.call(abi.encodeWithSelector(IERC20.transfer.selector, strategy, amount));
        if (!ok || (ret.length == 0 ? asset.code.length == 0 : !abi.decode(ret, (bool)))) {
            revert IERC4626.SafeERC20FailedOperation(asset);
        }
        emit IVaultCore.AssetsAllocated(strategy, amount);
    }

    /// @notice Acknowledges a recall event from a strategy.
    /// @dev The strategy itself is responsible for pushing assets back to the vault.
    ///      This function exists to emit the event and allow the StrategyManager to
    ///      coordinate the accounting.
    /// @param strategy Source strategy address.
    /// @param amount Amount expected to be returned by the strategy.
    function recallFromStrategy(address strategy, uint256 amount) internal {
        _checkManager();
        emit IVaultCore.AssetsRecalled(strategy, amount);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Reverts with VaultCoreUnauthorizedManager if the caller is not the strategy manager.
    function _checkManager() internal view {
        address caller = msg.sender;
        address manager = vaultCoreStorage()._strategyManager;
        if (caller != manager) revert IVaultCore.VaultCoreUnauthorizedManager(caller);
    }

    /// @notice Reverts if the configured strategy manager is currently executing `rebalance()`.
    /// @dev During a rebalance the vault's idle balance and the strategies' reported balances are
    ///      transiently inconsistent, so `totalAssets()` (and therefore the share price) cannot be
    ///      trusted. The vault's deposit/mint/withdraw/redeem entry points call this to reject
    ///      read-only reentrancy via a strategy callback. The manager is an external contract, so we
    ///      query its reentrancy status by staticcall — mirroring how `totalAssets()` reads it.
    function requireManagerNotRebalancing() internal view {
        address manager = vaultCoreStorage()._strategyManager;
        if (manager == address(0)) return;
        (bool ok, bytes memory data) = manager.staticcall(abi.encodeWithSignature("reentrancyGuardEntered()"));
        if (ok && data.length >= 32 && abi.decode(data, (bool))) {
            revert IVaultCore.VaultCoreManagerRebalancing();
        }
    }

    /// @notice Returns true while deposits are latched closed, by the vault ({managerSwapLatched}) or by the
    ///         configured strategy manager ({managerDepositsLatched}).
    function depositsLatched() internal view returns (bool) {
        return managerSwapLatched() || managerDepositsLatched();
    }

    /// @notice Returns true while a strategy-manager swap keeps the vault's deposits closed (#305).
    function managerSwapLatched() internal view returns (bool) {
        return vaultCoreRecoveryStorage()._managerSwapLatched;
    }

    /// @notice Returns true while the configured strategy manager latches deposits closed.
    /// @dev Reads the manager's `depositsLatched()` (`IStrategyManagerRecovery`), which a strategy force removal
    ///      sets (#270). No manager, or a manager whose read fails or returns short data (one without the
    ///      latch selector), counts as unlatched, mirroring {requireManagerNotRebalancing}. Any nonzero word
    ///      counts as latched, so a malformed answer keeps deposits closed rather than reverting the views.
    ///      A swap away from such a manager is stricter: there a failed read latches ({_releasesCleanly}).
    function managerDepositsLatched() internal view returns (bool) {
        address manager = vaultCoreStorage()._strategyManager;
        if (manager == address(0)) return false;
        (bool ok, uint256 latched) = _readWord(manager, IStrategyManagerRecovery.depositsLatched.selector);
        return ok && latched != 0;
    }

    /// @notice Reverts with {IVaultCore.VaultCoreDepositsLatched} while deposits are latched closed.
    /// @dev Called by the deposit/mint entry points. A force removal or a manager swap drops funds from the NAV,
    ///      so a depositor entering at the lower NAV would capture part of any funds that later return; the latch
    ///      keeps entries closed until an admin clears it. The error names the latch holder whose clear is due:
    ///      this vault for the manager-swap latch (checked first), else the strategy manager. Exits are not gated.
    function requireDepositsOpen() internal view {
        if (managerSwapLatched()) revert IVaultCore.VaultCoreDepositsLatched(address(this));
        if (managerDepositsLatched()) {
            revert IVaultCore.VaultCoreDepositsLatched(vaultCoreStorage()._strategyManager);
        }
    }

    /// @dev True only when `manager` verifiably strands nothing on a swap: both its `depositsLatched()` and its
    ///      `totalAllocated()` read succeed with a full word, and they report `false` and `0`. Any other answer,
    ///      including a revert, short return data or running out of gas, returns false, so the swap latches. The
    ///      old manager cannot then show that its strategies, or the strategies it force-removed, hold nothing.
    ///      On the last-resort route (a broken NAV read) the old manager still reports allocations or its own
    ///      sum overflows, so it latches either way. A false latch costs one admin call; a missed one reopens
    ///      the #270 donation capture.
    function _releasesCleanly(address manager) private view returns (bool) {
        (bool ok, uint256 word) = _readWord(manager, IStrategyManagerRecovery.depositsLatched.selector);
        if (!ok || word != 0) return false;
        (ok, word) = _readWord(manager, IStrategyManager.totalAllocated.selector);
        return ok && word == 0;
    }

    /// @dev Staticcalls `selector` on `target` and returns the first word of its answer. `ok` is false when the
    ///      call reverts or returns fewer than 32 bytes. At most 32 bytes of return data are copied, so an
    ///      oversized answer cannot exhaust the caller's gas.
    function _readWord(address target, bytes4 selector) private view returns (bool ok, uint256 word) {
        assembly ("memory-safe") {
            mstore(0x00, selector)
            ok := staticcall(gas(), target, 0x00, 0x04, 0x00, 0x20)
            ok := and(ok, gt(returndatasize(), 0x1f))
            word := mload(0x00)
        }
    }
}
