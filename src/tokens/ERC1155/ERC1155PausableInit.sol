// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";

/// @title ERC1155PausableInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-1155 Pausable extension recipe — registers the IPausable interface
///         (ERC-165; `_paused` is the zero default) and grants `admin_` the DEFAULT_ADMIN_ROLE that gates
///         `pause()`/`unpause()`. Delegatecalled by {Diamond.initialize} (through {MultiInit}) inside the
///         initializing window opened by the diamond, alongside the base {ERC1155Init}; it must NOT open its own
///         pre/postInitializer. The {ERC1155Pausable} facet adds no ERC-165 id of its own.
contract ERC1155PausableInit {
    function init(address admin_) external {
        PausableLib.__Pausable_init();
        AccessControlLib.__AccessControl_init(admin_);
    }
}
