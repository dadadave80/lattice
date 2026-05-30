// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IERC20} from "@lattice/interfaces/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/IERC4626.sol";
import {IVaultCore} from "@lattice/interfaces/IVaultCore.sol";
import {ERC4626Lib} from "@lattice/tokens/libraries/ERC4626Lib.sol";

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

/// @notice Storage struct for VaultCore module.
/// @custom:storage-location erc7201:lattice.storage.VaultCore
struct VaultCoreStorage {
    address _strategyManager;
}

/// @title VaultCoreLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library extending ERC-4626 vaults with strategy hooks for yield aggregation.
/// @dev All logic lives here; the VaultCore facet is a pure delegator. Storage is accessed
///      via ERC-7201 namespaced slot to avoid collisions in the Diamond proxy.
///
///      Architecture:
///      - The vault holds "idle" assets (its own ERC-20 balance of the underlying).
///      - When a StrategyManager is configured, it can direct the vault to PUSH assets to
///        external strategies via `allocateToStrategy`. The strategy later PUSHES back via
///        its own `withdraw` call.
///      - `totalAssets()` is overridden to include both idle and allocated assets so that
///        share price accurately reflects all vault assets regardless of location.
library VaultCoreLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function vaultCoreStorage() internal pure returns (VaultCoreStorage storage $) {
        assembly {
            $.slot := VAULT_CORE_STORAGE_SLOT
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
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IVaultCore interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IVAULTCORE_SLOT, true)
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
    /// @dev Overrides ERC4626Lib.totalAssets(). When a manager is set, adds the manager's
    ///      `totalAllocated()` view (which sums each strategy's self-reported balance).
    ///      Trust assumption: strategy balance reports are accurate.
    function totalAssets() internal view returns (uint256) {
        uint256 idle = idleAssets();
        address manager = vaultCoreStorage()._strategyManager;
        if (manager == address(0)) return idle;
        // IStrategyManager.totalAllocated() is the sum of IStrategy.totalAssetsManaged()
        // across all registered strategies.
        (bool ok, bytes memory data) = manager.staticcall(abi.encodeWithSignature("totalAllocated()"));
        if (!ok || data.length < 32) return idle;
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
    /// @param manager The new strategy manager address.
    function setStrategyManager(address manager) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _setStrategyManager(manager);
    }

    /// @dev Inner logic for setStrategyManager (no auth check — auth in outer).
    function _setStrategyManager(address manager) internal {
        if (manager == address(0)) revert IVaultCore.VaultCoreInvalidManager();
        vaultCoreStorage()._strategyManager = manager;
        emit IVaultCore.StrategyManagerSet(manager);
    }

    /// @notice Transfers idle assets to a strategy. Only callable by the strategy manager.
    /// @param strategy Destination strategy address.
    /// @param amount Amount of underlying asset to transfer.
    function allocateToStrategy(address strategy, uint256 amount) internal {
        _checkManager();
        address asset = ERC4626Lib.asset();
        (bool ok, bytes memory ret) = asset.call(abi.encodeWithSelector(IERC20.transfer.selector, strategy, amount));
        if (!ok || (ret.length > 0 && !abi.decode(ret, (bool)))) {
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
        address caller = ContextLib.msgSender();
        address manager = vaultCoreStorage()._strategyManager;
        if (caller != manager) revert IVaultCore.VaultCoreUnauthorizedManager(caller);
    }
}
