// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20PermitLib} from "@lattice/tokens/ERC20/libraries/ERC20PermitLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

/// @title ERC20PermitInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-20 Permit (ERC-2612) extension — seeds the EIP-712 domain and nonce
///         storage {ERC20Permit} builds its digest over, then registers IERC20Permit via ERC-165. The EIP-712
///         domain uses the token `name_` and version "1". Delegatecalled by {Diamond.initialize} (through
///         {MultiInit}) inside the initializing window opened by the diamond, alongside the base {ERC20Init}; it
///         must NOT open its own pre/postInitializer.
contract ERC20PermitInit {
    function init(string memory name_) external {
        EIP712Lib.__EIP712_init(name_, "1");
        NoncesLib.__Nonces_init();
        ERC20PermitLib.__ERC20Permit_init();
    }
}
