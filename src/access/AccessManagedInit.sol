// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessManagedLib} from "@lattice/access/libraries/AccessManagedLib.sol";

/// @title AccessManagedInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an AccessManaged diamond — points the contract at its external
///         AccessManager `authority` and registers the IAccessManaged interface (ERC-165). Delegatecalled by
///         {Lattice.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer;
///         the `__AccessManaged_init` guard passes because the window is already open). Reverts with
///         {AccessManagedInvalidAuthority} if `authority` is not a contract.
/// @custom:lattice-kind step
contract AccessManagedInit {
    /// @notice Seeds the AccessManaged module. MUST be invoked via the diamond's `initialize` `_init` delegatecall.
    /// @param authority The AccessManager authority governing this contract.
    /// @custom:lattice-initializes AccessManaged;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param authority authority rule=nonzero-contract;
    /// @custom:lattice-registers-interfaces
    function init(address authority) external {
        AccessManagedLib.__AccessManaged_init(authority);
    }
}
