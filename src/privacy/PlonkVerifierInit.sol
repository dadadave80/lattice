// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PlonkVerifierLib} from "@lattice/privacy/libraries/PlonkVerifierLib.sol";

/// @title PlonkVerifierInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a PLONK verifier diamond — registers the IPlonkVerifier interface (ERC-165).
///         The verifier is a stateless, permissionless primitive (anyone may verify a proof), so there is NO
///         AccessControl in the recipe. Delegatecalled by {Diamond.initialize} inside the initializing window
///         (so it must NOT open its own pre/postInitializer; the `__PlonkVerifier_init` guard passes because the
///         window is already open).
contract PlonkVerifierInit {
    /// @notice Runs the PLONK verifier module initializer. MUST be invoked via the diamond's `initialize`
    ///         `_init` delegatecall.
    function init() external {
        PlonkVerifierLib.__PlonkVerifier_init();
    }
}
