// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC6538RegistryLib} from "@lattice/privacy/libraries/ERC6538RegistryLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";

/// @title ERC6538RegistryInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an ERC-6538 stealth meta-address registry diamond — seeds the EIP-712 domain
///         (name "ERC6538Registry" / version "1.0") the registry reuses for `registerKeysOnBehalf` signature
///         hashing, then registers the IERC6538Registry interface (ERC-165). Delegatecalled by
///         {Lattice.initialize} inside the initializing window (so it must NOT open its own pre/postInitializer;
///         each `__*_init` guard passes because the window is already open). ERC-5267 `eip712Domain()` discovery
///         comes from the separate `EIP712` facet cut by the canonical registry recipe.
/// @custom:lattice-kind bundle
contract ERC6538RegistryInit {
    /// @notice Runs the EIP-712 + registry module initializers. MUST be invoked via the diamond's `initialize`
    ///         `_init` delegatecall.
    /// @custom:lattice-initializes EIP712 with version=1.0;
    /// @custom:lattice-initializes ERC6538Registry;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence EIP712;ERC6538Registry;
    /// @custom:lattice-param none;
    /// @custom:lattice-registers-interfaces
    function init() external {
        EIP712Lib.__EIP712_init("ERC6538Registry", "1.0");
        ERC6538RegistryLib.__ERC6538Registry_init();
    }
}
