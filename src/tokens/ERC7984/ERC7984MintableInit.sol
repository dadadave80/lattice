// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC7984Lib} from "@lattice/tokens/ERC7984/libraries/ERC7984Lib.sol";
import {ERC7984MintableLib, ERC7984_MINTER_ROLE} from "@lattice/tokens/ERC7984/libraries/ERC7984MintableLib.sol";

/// @title ERC7984MintableInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a mintable ERC-7984 (confidential fungible token) diamond: seeds the base
///         token (name, symbol, contract URI, the chain's coprocessor configuration and IERC7984 via ERC-165),
///         AccessControl and IERC7984Mintable, then grants `ERC7984_MINTER_ROLE` to the minter. Delegatecalled by
///         {Lattice.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer).
/// @dev `__ERC7984_init` runs first, so its diamond-caller deny-list, the EIP-7702 (code delegation for
///      externally owned accounts) host refusal and the chain table all run before any role is written.
/// @custom:lattice-kind bundle
contract ERC7984MintableInit {
    /// @notice Runs the ERC-7984, AccessControl and ERC-7984 mint initializers and grants the minter role.
    ///         MUST be invoked via the diamond's `initialize` `_init` delegatecall.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`, which administers `ERC7984_MINTER_ROLE`.
    /// @param minter The address granted `ERC7984_MINTER_ROLE`.
    /// @param name_ Token name.
    /// @param symbol_ Token symbol.
    /// @param contractURI_ Token contract URI.
    /// @custom:lattice-initializes ERC7984;
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-initializes ERC7984Mintable;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence ERC7984;AccessControl;ERC7984Mintable;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-param minter;
    /// @custom:lattice-param name_;
    /// @custom:lattice-param symbol_;
    /// @custom:lattice-param contractURI_;
    /// @custom:lattice-registers-interfaces
    function init(address admin, address minter, string memory name_, string memory symbol_, string memory contractURI_)
        external
    {
        ERC7984Lib.__ERC7984_init(name_, symbol_, contractURI_);
        AccessControlLib.__AccessControl_init(admin);
        ERC7984MintableLib.__ERC7984Mintable_init();
        AccessControlLib._grantRole(ERC7984_MINTER_ROLE, minter);
    }
}
