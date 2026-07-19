// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessManager} from "@lattice/access/AccessManager.sol";
import {AccessManagerLib} from "@lattice/access/libraries/AccessManagerLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @title AccessManagerStandalone
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/manager/AccessManager.sol)
/// @notice Non-Diamond deployable. Inherits all logic from `AccessManager`;
///         adds a constructor-based initializer for direct deployment.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract AccessManagerStandalone is AccessManager {
    constructor(address initialAdmin) {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        AccessManagerLib.__AccessManager_init(initialAdmin);
        InitializableLib.postInitializer(s);
    }
}
