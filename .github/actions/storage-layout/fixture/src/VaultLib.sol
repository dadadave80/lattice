// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice A position, nested in VaultStorage through a mapping and an array.
struct Position {
    uint128 amount;
    uint64 since;
}

/// @custom:storage-location erc7201:fixture.storage.Vault
struct VaultStorage {
    address owner;
    uint96 fee;
    mapping(address account => Position) positions;
    Position[] history;
}

/// @custom:storage-location erc7201:fixture.storage.Config
struct ConfigStorage {
    uint256 cap;
    bool paused;
}

/// @title VaultLib
/// @notice Storage-safety Action test fixture: two ERC-7201 namespaces and one nested struct.
library VaultLib {
    /// @dev `cast index-erc7201 fixture.storage.Vault`.
    bytes32 internal constant VAULT_STORAGE_SLOT = 0xd8ed81b9bd71049e7f9a03b7ecdaa60a314d16d0d1fe77f622a86c25512e3400;
    /// @dev `cast index-erc7201 fixture.storage.Config`.
    bytes32 internal constant CONFIG_STORAGE_SLOT = 0x4cde6f039520bb9e87112bc5a05a8169891a850e911c7b3c2d029420f1388900;

    function vault() internal pure returns (VaultStorage storage s) {
        assembly ("memory-safe") {
            s.slot := VAULT_STORAGE_SLOT
        }
    }

    function config() internal pure returns (ConfigStorage storage s) {
        assembly ("memory-safe") {
            s.slot := CONFIG_STORAGE_SLOT
        }
    }
}
