// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";

/// @title Multicall Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Multicall.sol)
/// @notice Utility library for batching multiple calls to the same contract in one transaction.
/// @dev This is a stateless utility library with no ERC-7201 storage slot or initializer.
/// Each call is executed as a `delegatecall` from the calling contract's context, so it
/// runs with the same storage, value, and sender as the outer call.
///
/// ERC-2771 / trusted-forwarder support: when `msg.sender != ContextLib.msgSender()` (i.e. the
/// call is relayed through a trusted forwarder), each subcall payload receives the ERC-2771
/// context suffix (the original sender address as 20 bytes appended to the calldata) so that
/// `ContextLib.msgSender()` inside the receiving facet resolves to the correct EOA.
/// This matches OZ Multicall v5.1.0 behaviour. If no trusted forwarder is in use the suffix
/// length is zero and calldata is forwarded unchanged.
library MulticallLib {
    /// @notice Executes a batch of calls on the calling contract via `delegatecall`.
    /// @dev If any individual call reverts, the whole batch reverts with the same revert data.
    /// The calls are routed through the Diamond's fallback dispatcher, allowing cross-facet batching.
    /// @param data An array of ABI-encoded calldata payloads to execute.
    /// @return results An array of raw return bytes from each call, in the same order as `data`.
    function multicall(bytes[] calldata data) internal returns (bytes[] memory results) {
        address sender = ContextLib.msgSender();
        results = new bytes[](data.length);
        for (uint256 i; i < data.length; ++i) {
            bytes memory callData;
            if (msg.sender != sender) {
                // Trusted forwarder in use: append the original sender as ERC-2771 context suffix
                // so that ContextLib.msgSender() resolves correctly inside each subcall.
                callData = abi.encodePacked(data[i], sender);
            } else {
                callData = data[i];
            }
            (bool ok, bytes memory ret) = address(this).delegatecall(callData);
            if (!ok) {
                assembly {
                    let len := mload(ret)
                    revert(add(0x20, ret), len)
                }
            }
            results[i] = ret;
        }
    }
}
