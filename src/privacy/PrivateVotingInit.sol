// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PrivateVotingLib} from "@lattice/privacy/libraries/PrivateVotingLib.sol";
import {SemaphoreLib} from "@lattice/privacy/libraries/SemaphoreLib.sol";

/// @title PrivateVotingInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a PrivateVoting diamond — seeds the underlying Semaphore module with its
///         off-chain proof verifier and registers both the ISemaphore and IPrivateVoting interfaces (ERC-165).
///         Poll and group admin are per-group (set by `createGroup`), so there is NO AccessControl in the recipe.
///         Delegatecalled by {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer; each `__*_init` guard passes because the window is already open).
contract PrivateVotingInit {
    /// @notice Runs the Semaphore + PrivateVoting module initializers. MUST be invoked via the diamond's
    ///         `initialize` `_init` delegatecall.
    /// @param verifier The {ISemaphoreVerifier} contract address used to check the anonymous vote proofs.
    function init(address verifier) external {
        SemaphoreLib.__Semaphore_init(verifier);
        PrivateVotingLib.__PrivateVoting_init();
    }
}
