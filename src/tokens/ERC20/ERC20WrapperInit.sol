// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20WrapperLib} from "@lattice/tokens/ERC20/libraries/ERC20WrapperLib.sol";

/// @title ERC20WrapperInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ERC-20 Wrapper extension — records the underlying token (caching its
///         decimals) and registers IERC20Wrapper via ERC-165. Delegatecalled by {Diamond.initialize} (through
///         {MultiInit}) inside the initializing window opened by the diamond, alongside the base {ERC20Init}; it
///         must NOT open its own pre/postInitializer. Reverts with {IERC20Wrapper-ERC20InvalidUnderlying} when
///         `underlying_` is the wrapper itself.
contract ERC20WrapperInit {
    function init(address underlying_) external {
        ERC20WrapperLib.__ERC20Wrapper_init(underlying_);
    }
}
