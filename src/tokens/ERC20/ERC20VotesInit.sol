// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

/// @title ERC20VotesInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-20 Votes extension recipe — seeds the EIP-712 domain (name `name_`,
///         version "1") and nonce storage the `delegateBySig` digest reads, the checkpoint/clock state (registering
///         IVotes; the error-only IERC20Votes has no ERC-165 id), and grants `admin_` the DEFAULT_ADMIN_ROLE that
///         gates a consumer's minting authority. Delegatecalled by {Lattice.initialize} (through {MultiInit})
///         inside the initializing window opened by the diamond, alongside the base {ERC20Init}; it must NOT open
///         its own pre/postInitializer.
/// @custom:lattice-kind bundle
contract ERC20VotesInit {
    /// @custom:lattice-initializes EIP712 with version=1;
    /// @custom:lattice-initializes Nonces;
    /// @custom:lattice-initializes Votes;
    /// @custom:lattice-initializes AccessControl;
    /// @custom:lattice-after ERC20 convention domain-name-matches-token-name;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence EIP712;Nonces;Votes;AccessControl;
    /// @custom:lattice-param name_;
    /// @custom:lattice-param admin_ authority;
    /// @custom:lattice-registers-interfaces
    function init(string memory name_, address admin_) external {
        EIP712Lib.__EIP712_init(name_, "1");
        NoncesLib.__Nonces_init();
        VotesLib.__Votes_init();
        AccessControlLib.__AccessControl_init(admin_);
    }
}
