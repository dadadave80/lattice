// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

/// @title Nonces
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Nonces.sol)
/// @notice Thin facet exposing the `nonces(address)` view for per-account nonce tracking.
/// @dev Other nonce operations (useNonce, useCheckedNonce) are internal helpers consumed
///      by other modules (e.g. ERC20Permit). Only the query function needs a public entry point.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract Nonces {
    /// @notice Returns the current nonce for the given owner.
    /// @param owner The address to query.
    /// @return The current nonce for the account.
    function nonces(address owner) public view virtual returns (uint256) {
        return NoncesLib.nonces(owner);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect Nonces methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `nonces(address)` 0x7ecebe00
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"7ecebe00";
    }
}
