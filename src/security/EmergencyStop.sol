// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IEmergencyStop} from "@lattice/interfaces/IEmergencyStop.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";

/// @title EmergencyStop
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Pausable.sol)
/// @notice Thin Diamond facet that exposes multi-guardian emergency stop functionality.
/// @dev All logic lives in {EmergencyStopLib}. This contract is stateless and forwards
///      every call to the library. Inherit this in your Diamond facet to add emergency-stop.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract EmergencyStop is IEmergencyStop {
    /// @inheritdoc IEmergencyStop
    function isStopped() public view virtual returns (bool) {
        return EmergencyStopLib.isStopped();
    }

    /// @inheritdoc IEmergencyStop
    function isGuardian(address account) public view virtual returns (bool) {
        return EmergencyStopLib.isGuardian(account);
    }

    /// @inheritdoc IEmergencyStop
    function stoppedReason() public view virtual returns (string memory) {
        return EmergencyStopLib.stoppedReason();
    }

    /// @inheritdoc IEmergencyStop
    function emergencyStop(string calldata reason) public virtual {
        EmergencyStopLib.emergencyStop(reason);
    }

    /// @inheritdoc IEmergencyStop
    function emergencyResume() public virtual {
        EmergencyStopLib.emergencyResume();
    }

    /// @inheritdoc IEmergencyStop
    function addGuardian(address guardian) public virtual {
        EmergencyStopLib.addGuardian(guardian);
    }

    /// @inheritdoc IEmergencyStop
    function removeGuardian(address guardian) public virtual {
        EmergencyStopLib.removeGuardian(guardian);
    }
}
