// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessManagedLib} from "@lattice/access/libraries/AccessManagedLib.sol";
import {IAccessManaged} from "@lattice/interfaces/access/IAccessManaged.sol";

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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect AccessManaged methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `authority()` 0xbf7e214f
    ///      `isConsumingScheduledOp()` 0x8fb36037
    ///      `setAuthority(address)` 0x7a9e5e4b
    ///      `setConsumingScheduledOp(bool)` 0xafe75bce
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"bf7e214f8fb360377a9e5e4bafe75bce";
    }
}
