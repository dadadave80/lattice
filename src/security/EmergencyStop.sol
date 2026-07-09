// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IEmergencyStop} from "@lattice/interfaces/security/IEmergencyStop.sol";
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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect EmergencyStop methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `addGuardian(address)` 0xa526d83b
    ///      `emergencyResume()` 0x93c87f03
    ///      `emergencyStop(string)` 0xb1e3268b
    ///      `isGuardian(address)` 0x0c68ba21
    ///      `isStopped()` 0x3f683b6a
    ///      `removeGuardian(address)` 0x71404156
    ///      `stoppedReason()` 0x5b0b0c07
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"a526d83b93c87f03b1e3268b0c68ba213f683b6a714041565b0b0c07";
    }
}
