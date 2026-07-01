// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Groth16VerifierLib} from "@lattice/privacy/libraries/Groth16VerifierLib.sol";

/// @title Groth16VerifierInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a Groth16 verifier diamond — registers the IGroth16Verifier interface
///         (ERC-165). The verifier is a stateless, permissionless primitive (anyone may verify a proof), so there
///         is NO AccessControl in the recipe. Delegatecalled by {Diamond.initialize} inside the initializing
///         window (so it must NOT open its own pre/postInitializer; the `__Groth16Verifier_init` guard passes
///         because the window is already open).
contract Groth16VerifierInit {
    /// @notice Runs the Groth16 verifier module initializer. MUST be invoked via the diamond's `initialize`
    ///         `_init` delegatecall.
    function init() external {
        Groth16VerifierLib.__Groth16Verifier_init();
    }
}
