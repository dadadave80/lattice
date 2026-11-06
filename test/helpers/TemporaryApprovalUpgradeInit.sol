// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20TemporaryApprovalLib} from "@lattice/tokens/ERC20/libraries/ERC20TemporaryApprovalLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";

/// @title TemporaryApprovalUpgradeInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice App-specific upgrade wrapper opening version two for the production extension initializer.
contract TemporaryApprovalUpgradeInit is Initializable {
    function init() external reinitializer(2) {
        ERC20TemporaryApprovalLib.__ERC20TemporaryApproval_init();
    }
}
