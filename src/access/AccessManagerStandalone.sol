// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessManager} from "@lattice/access/AccessManager.sol";
import {AccessManagerLib} from "@lattice/access/libraries/AccessManagerLib.sol";

/// @title AccessManagerStandalone
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/manager/AccessManager.sol)
/// @notice Non-Diamond deployable. Inherits all logic from `AccessManager`;
///         adds a constructor-based initializer for direct deployment.
contract AccessManagerStandalone is AccessManager {
    constructor(address initialAdmin) {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessManagerLib.__AccessManager_init(initialAdmin);
        InitializableLib.postInitializer(s);
    }
}
