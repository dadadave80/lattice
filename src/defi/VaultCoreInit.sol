// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {VaultCoreLib} from "@lattice/defi/libraries/VaultCoreLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";

/// @title VaultCoreInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a VaultCore diamond — an ERC-4626 vault extended with strategy hooks. Runs
///         the module initializers in dependency order inside a single initializing window: AccessControl
///         (grants `DEFAULT_ADMIN_ROLE` to `admin`, gating strategy-manager changes), ERC-20 (share metadata),
///         ERC-4626 (underlying asset + offset), then VaultCore (registers IVaultCore and IVaultCoreRecovery via ERC-165).
///         Delegatecalled by {Diamond.initialize} inside the initializing window — it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open.
/// @custom:lattice-kind bundle
contract VaultCoreInit {
    /// @notice Seeds access control, the ERC-20 share metadata, the ERC-4626 vault params, and VaultCore.
    /// @param asset_ The underlying ERC-20 asset the vault holds.
    /// @param name_ The vault share token name.
    /// @param symbol_ The vault share token symbol.
    /// @param admin_ The account granted `DEFAULT_ADMIN_ROLE` (may set the strategy manager).
    /// @param decimalsOffset_ Virtual-share decimals offset for inflation-attack mitigation (usually 0).
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes ERC20;
    /// @custom:lattice-initializes ERC4626;
    /// @custom:lattice-initializes VaultCore;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;ERC20;ERC4626;VaultCore;
    /// @custom:lattice-param asset_;
    /// @custom:lattice-param name_;
    /// @custom:lattice-param symbol_;
    /// @custom:lattice-param admin_ authority;
    /// @custom:lattice-param decimalsOffset_;
    /// @custom:lattice-registers-interfaces
    function init(address asset_, string memory name_, string memory symbol_, address admin_, uint8 decimalsOffset_)
        external
    {
        AccessControlLib.__AccessControl_init(admin_);
        ERC20Lib.__ERC20_init(name_, symbol_);
        ERC4626Lib.__ERC4626_init(asset_, decimalsOffset_);
        VaultCoreLib.__VaultCore_init();
    }
}
