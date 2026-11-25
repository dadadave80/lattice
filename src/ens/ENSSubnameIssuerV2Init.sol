// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ENSSubnameIssuerV2Lib} from "@lattice/ens/libraries/ENSSubnameIssuerV2Lib.sol";

/// @title ENSSubnameIssuerV2Init
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Configures the Universal Helper and registers the issuer's interface during diamond initialization.
/// @custom:lattice-kind step
contract ENSSubnameIssuerV2Init {
    /// @notice Initializes the ENSv2 subname issuer once inside the diamond's initializing window.
    /// @param helper The verified Universal Helper on this chain.
    /// @custom:lattice-initializes ENSSubnameIssuerV2;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param helper;
    /// @custom:lattice-registers-interfaces
    function init(address helper) external {
        ENSSubnameIssuerV2Lib.__ENSSubnameIssuerV2_init(helper);
    }
}
