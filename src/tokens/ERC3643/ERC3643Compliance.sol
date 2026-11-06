// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICompliance} from "@lattice/interfaces/tokens/erc3643/ICompliance.sol";
import {ERC3643ComplianceLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ComplianceLib.sol";

/// @title ERC3643Compliance
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Stateless standard Compliance facet for the closed ERC-3643 suite.
/// @custom:lattice-source ERC-3643 CC0 standard
/// @custom:lattice-requires OwnableFacet convention compliance-binding-administration;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches lattice.storage.ERC3643Compliance;
/// @custom:lattice-touches transient:lattice.storage.ERC3643Execution;
/// @custom:lattice-seam none;
/// @custom:lattice-init ERC3643Init
contract ERC3643Compliance is ICompliance {
    function bindToken(address token) external {
        ERC3643ComplianceLib.bindToken(token);
    }

    function unbindToken(address token) external {
        ERC3643ComplianceLib.unbindToken(token);
    }

    function getTokenBound() external view returns (address) {
        return ERC3643ComplianceLib.getTokenBound();
    }

    function canTransfer(address from, address to, uint256 amount) external pure returns (bool) {
        return ERC3643ComplianceLib.canTransfer(from, to, amount);
    }

    function transferred(address from, address to, uint256 amount) external {
        ERC3643ComplianceLib.transferred(from, to, amount);
    }

    function created(address to, uint256 amount) external {
        ERC3643ComplianceLib.created(to, amount);
    }

    function destroyed(address from, uint256 amount) external {
        ERC3643ComplianceLib.destroyed(from, amount);
    }

    /// @notice ERC-8153 packed selectors; excludes exportSelectors itself.
    function exportSelectors() external pure returns (bytes memory) {
        return hex"3ff5aa02e46638e65f8dead38d2ea7726a3edf288baf29b440db3b50";
    }
}
