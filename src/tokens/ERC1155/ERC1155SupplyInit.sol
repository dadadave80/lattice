// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1155SupplyLib} from "@lattice/tokens/ERC1155/libraries/ERC1155SupplyLib.sol";

/// @title ERC1155SupplyInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-1155 Supply extension — registers IERC1155Supply via ERC-165 (the
///         counters start at zero). Delegatecalled by {Diamond.initialize} (through {MultiInit}) inside the
///         initializing window opened by the diamond, alongside the base {ERC1155Init}; it must NOT open its own
///         pre/postInitializer. Run it only on a diamond that holds no balances yet (see {ERC1155SupplyLib}).
contract ERC1155SupplyInit {
    function init() external {
        ERC1155SupplyLib.__ERC1155Supply_init();
    }
}
