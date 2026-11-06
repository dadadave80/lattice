// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {SafeHarborAdopterLib} from "@lattice/governance/libraries/SafeHarborAdopterLib.sol";

/// @title SafeHarborAdopterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a SafeHarborAdopter diamond — seeds AccessControl so the adoption +
///         configuration setters are `SAFE_HARBOR_ADMIN_ROLE`-gated (that role is administered by
///         `DEFAULT_ADMIN_ROLE`, granted to `admin`) and wires the SEAL registry + factory while registering
///         the ISafeHarborAdopter interface (ERC-165). Delegatecalled by {Diamond.initialize} inside the
///         initializing window (so it must NOT open its own pre/postInitializer; each `__*_init` guard passes
///         because the window is already open). Companion to the {ERC2981Init} pattern —
///         a first-class production deploy artifact.
/// @custom:lattice-kind bundle
contract SafeHarborAdopterInit {
    /// @notice Runs the access-control + safe-harbor module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (administers `SAFE_HARBOR_ADMIN_ROLE`).
    /// @param registry The SEAL SafeHarborRegistry for this chain (must be non-zero).
    /// @param factory The SEAL AgreementFactory for this chain (zero allowed; disables `createAndAdopt`).
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes SafeHarborAdopter;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence AccessControl;SafeHarborAdopter;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-param registry;
    /// @custom:lattice-param factory;
    /// @custom:lattice-registers-interfaces
    function init(address admin, address registry, address factory) external {
        AccessControlLib.__AccessControl_init(admin);
        SafeHarborAdopterLib.__SafeHarborAdopter_init(registry, factory);
    }
}
