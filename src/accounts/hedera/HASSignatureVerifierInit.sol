// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HASSignatureVerifierLib} from "@lattice/accounts/hedera/HASSignatureVerifierLib.sol";

/// @title HASSignatureVerifierInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer registering the IHASSignatureVerifier interface (ERC-165). Stateless module:
///         nothing else to seed. Delegatecalled by {Diamond.initialize} inside the initializing window.
contract HASSignatureVerifierInit {
    function init() external {
        HASSignatureVerifierLib.__HASSignatureVerifier_init();
    }
}
