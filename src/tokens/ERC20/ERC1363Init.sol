// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1363Lib} from "@lattice/tokens/ERC20/libraries/ERC1363Lib.sol";

/// @title ERC1363Init
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-1363 extension — registers IERC1363 via ERC-165.
///         Delegatecalled by {Diamond.initialize} (through {MultiInit}) inside the initializing window opened by
///         the diamond, alongside the base {ERC20Init}; it must NOT open its own pre/postInitializer.
contract ERC1363Init {
    function init() external {
        ERC1363Lib.__ERC1363_init();
    }
}
