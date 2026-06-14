// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IMulticall} from "@lattice/interfaces/IMulticall.sol";
import {MulticallLib} from "@lattice/utils/libraries/MulticallLib.sol";

/// @title Multicall
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Multicall.sol)
/// @notice Thin Diamond facet that enables batched calls in a single transaction.
/// @dev All logic lives in {MulticallLib}. This contract is stateless and has no initializer.
/// Inherit this in your Diamond facet to enable multicall functionality.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract Multicall is IMulticall {
    /// @inheritdoc IMulticall
    function multicall(bytes[] calldata data) public virtual returns (bytes[] memory results) {
        return MulticallLib.multicall(data);
    }
}
