// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ConfigStorage, VaultStorage} from "../src/VaultLib.sol";

/// @notice Compile-only probe: one state variable per guarded struct, so solc emits its layout.
contract StorageProbe {
    VaultStorage internal vault;
    ConfigStorage internal config;
}
