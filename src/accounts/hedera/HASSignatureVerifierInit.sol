// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HASSignatureVerifierLib} from "@lattice/accounts/hedera/HASSignatureVerifierLib.sol";

/// @title HASSignatureVerifierInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer registering the IHASSignatureVerifier interface (ERC-165). Stateless module:
///         nothing else to seed. Delegatecalled by {Diamond.initialize} inside the initializing window.
/// @custom:lattice-kind step
contract HASSignatureVerifierInit {
    /// @custom:lattice-initializes HASSignatureVerifier;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param none;
    /// @custom:lattice-registers-interfaces
    function init() external {
        HASSignatureVerifierLib.__HASSignatureVerifier_init();
    }
}
