// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20CappedLib} from "@lattice/tokens/ERC20/libraries/ERC20CappedLib.sol";

/// @title ERC20CappedInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-20 Capped extension — seeds the supply cap and registers IERC20Capped
///         via ERC-165. Delegatecalled by {Diamond.initialize} (through {MultiInit}) inside the initializing window
///         opened by the diamond, alongside the base {ERC20Init}; it must NOT open its own pre/postInitializer.
///         Reverts with {IERC20Capped-ERC20InvalidCap} when `cap_` is zero.
contract ERC20CappedInit {
    function init(uint256 cap_) external {
        ERC20CappedLib.__ERC20Capped_init(cap_);
    }
}
