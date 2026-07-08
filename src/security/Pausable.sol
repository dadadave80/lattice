// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect Pausable methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `pause()` 0x8456cb59
    ///      `paused()` 0x5c975abb
    ///      `unpause()` 0x3f4ba83a
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"8456cb595c975abb3f4ba83a";
    }
}
