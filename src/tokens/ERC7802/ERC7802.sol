// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC7802} from "@lattice/interfaces/external/IERC7802.sol";
import {ERC7802Lib} from "@lattice/tokens/ERC7802/libraries/ERC7802Lib.sol";

/// @title ERC7802
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice ERC-7802 crosschain-native ERC-20 extension facet: a trusted bridge (holder of
///         `CROSSCHAIN_BRIDGE_ROLE`) mints on the destination chain and burns on the source. Mount
///         alongside the {ERC20} facet; pairs with a {BridgeERC7802} that holds the role.
/// @dev Stateless delegator — logic in {ERC7802Lib}, balances/roles reuse the ERC20 + AccessControl storage.
/// @custom:lattice-version 0.1.0
contract ERC7802 is IERC7802 {
    /// @inheritdoc IERC7802
    function crosschainMint(address _to, uint256 _amount) external virtual override {
        ERC7802Lib.crosschainMint(_to, _amount);
    }

    /// @inheritdoc IERC7802
    function crosschainBurn(address _from, uint256 _amount) external virtual override {
        ERC7802Lib.crosschainBurn(_from, _amount);
    }
}
