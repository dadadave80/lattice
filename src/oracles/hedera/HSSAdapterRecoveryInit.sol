// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HSSAdapterLib} from "@lattice/oracles/hedera/HSSAdapterLib.sol";

/// @title HSSAdapterRecoveryInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Registers the recovery interface during an upgrade initialization window; does not grant roles.
/// @dev Cancel and reschedule pre-upgrade raw jobs. Their completion cannot authenticate a generation.
contract HSSAdapterRecoveryInit {
    function init() external {
        HSSAdapterLib.__HSSAdapter_init();
    }
}
