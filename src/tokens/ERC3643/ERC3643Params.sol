// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Concrete initialization parameters for the immutable ERC-3643 profile.
/// @dev Zero storage/compliance addresses select the co-located components. The external store must
///      already bind the factory-predicted token address; external compliance must permit its real binding.
struct ERC3643Params {
    address owner;
    address[] agents;
    string name;
    string symbol;
    uint8 decimals;
    address onchainID;
    address identityStorage;
    address compliance;
    bool temporaryApproval;
}
