// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPausable} from "@lattice/interfaces/IPausable.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";

/// @title Pausable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Pausable.sol)
/// @notice Thin Diamond facet that exposes pause/unpause lifecycle control.
/// @dev All logic lives in {PausableLib}. This contract is stateless and forwards
/// every call to the library. Inherit this in your Diamond facet to add pausability.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract Pausable is IPausable {
    /// @inheritdoc IPausable
    function paused() public view virtual returns (bool) {
        return PausableLib.paused();
    }

    /// @inheritdoc IPausable
    function pause() public virtual {
        PausableLib.pause();
    }

    /// @inheritdoc IPausable
    function unpause() public virtual {
        PausableLib.unpause();
    }
}
