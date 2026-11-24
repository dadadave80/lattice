// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC7984Lib} from "@lattice/tokens/ERC7984/libraries/ERC7984Lib.sol";

/// @title ERC7984Init
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a base ERC-7984 (confidential fungible token) diamond: seeds name, symbol and
///         contract URI, pins the coprocessor configuration for the chain and registers IERC7984 via ERC-165.
///         Delegatecalled by {Lattice.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer). Every check lives in {ERC7984Lib.__ERC7984_init}; this contract only calls it.
/// @custom:lattice-kind step
contract ERC7984Init {
    /// @custom:lattice-initializes ERC7984;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param name_;
    /// @custom:lattice-param symbol_;
    /// @custom:lattice-param contractURI_;
    /// @custom:lattice-registers-interfaces
    function init(string memory name_, string memory symbol_, string memory contractURI_) external {
        ERC7984Lib.__ERC7984_init(name_, symbol_, contractURI_);
    }
}
