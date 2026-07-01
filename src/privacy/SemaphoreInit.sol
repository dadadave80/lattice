// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {SemaphoreLib} from "@lattice/privacy/libraries/SemaphoreLib.sol";

/// @title SemaphoreInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Semaphore diamond — seeds AccessControl (so the `setVerifier` admin setter
///         is `DEFAULT_ADMIN_ROLE`-gated) and registers the ISemaphore interface (ERC-165) with its off-chain
///         proof verifier. Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT
///         open its own pre/postInitializer; each `__*_init` guard passes because the window is already open).
contract SemaphoreInit {
    /// @notice Runs the access-control + Semaphore module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (controls `setVerifier`).
    /// @param verifier The {ISemaphoreVerifier} contract address used to check Semaphore proofs.
    function init(address admin, address verifier) external {
        AccessControlLib.__AccessControl_init(admin);
        SemaphoreLib.__Semaphore_init(verifier);
    }
}
