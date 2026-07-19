// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessManager} from "@lattice/access/AccessManager.sol";
import {AccessManagerLib} from "@lattice/access/libraries/AccessManagerLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";

/// @title AccessManagerStandalone
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/manager/AccessManager.sol)
/// @notice Non-Diamond deployable. Inherits all logic from `AccessManager`;
///         adds a constructor-based initializer for direct deployment.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract AccessManagerStandalone is AccessManager, Initializable {
    constructor(address initialAdmin) initializer {
        AccessManagerLib.__AccessManager_init(initialAdmin);
    }
}
