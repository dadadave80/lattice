// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20TemporaryApprovalLib} from "@lattice/tokens/ERC20/libraries/ERC20TemporaryApprovalLib.sol";

/// @title ERC20TemporaryApprovalInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Registers the ERC-7674 interface in an existing diamond initializing window.
/// @dev Standalone so burnable, votes, flash-mint and vault recipes can compose the same initializer.
/// @custom:lattice-kind step
contract ERC20TemporaryApprovalInit {
    /// @custom:lattice-initializes ERC20TemporaryApproval;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param none;
    /// @custom:lattice-registers-interfaces
    function init() external {
        ERC20TemporaryApprovalLib.__ERC20TemporaryApproval_init();
    }
}
