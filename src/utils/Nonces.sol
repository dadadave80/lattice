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
}
