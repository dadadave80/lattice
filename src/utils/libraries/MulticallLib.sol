// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Multicall Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Utility library for batching multiple calls to the same contract in one transaction.
/// @dev This is a stateless utility library with no ERC-7201 storage slot or initializer.
/// Each call is executed as a `delegatecall` from the calling contract's context, so it
/// runs with the same storage, value, and sender as the outer call.
library MulticallLib {
    /// @notice Executes a batch of calls on the calling contract via `delegatecall`.
    /// @dev If any individual call reverts, the whole batch reverts with the same revert data.
    /// The calls are routed through the Diamond's fallback dispatcher, allowing cross-facet batching.
    /// @param data An array of ABI-encoded calldata payloads to execute.
    /// @return results An array of raw return bytes from each call, in the same order as `data`.
    function multicall(bytes[] calldata data) internal returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool ok, bytes memory ret) = address(this).delegatecall(data[i]);
            if (!ok) {
                assembly {
                    let returnDataSize := mload(ret)
                    revert(add(32, ret), returnDataSize)
                }
            }
            results[i] = ret;
        }
    }
}
