// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessManagedLib} from "@lattice/access/libraries/AccessManagedLib.sol";
import {IAccessManaged} from "@lattice/interfaces/IAccessManaged.sol";

/// @title AccessManaged
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/manager/AccessManaged.sol)
/// @notice Diamond facet for contracts gated by an external AccessManager.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract AccessManaged is IAccessManaged {
    function authority() external view virtual override returns (address) {
        return AccessManagedLib.authority();
    }

    function setAuthority(address newAuthority) external virtual override {
        AccessManagedLib.setAuthority(newAuthority);
    }

    function isConsumingScheduledOp() external view virtual override returns (bytes4) {
        return AccessManagedLib.isConsumingScheduledOp();
    }

    function setConsumingScheduledOp(bool consuming) external virtual override {
        AccessManagedLib.setConsumingScheduledOp(consuming);
    }
}
