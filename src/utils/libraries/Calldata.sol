// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.3.0) (utils/Calldata.sol)

pragma solidity ^0.8.20;

/**
 * @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Calldata.sol)
 * @dev Helper library for manipulating objects in calldata.
 */
library Calldata {
    // slither-disable-next-line write-after-write
    function emptyBytes() internal pure returns (bytes calldata result) {
        assembly ("memory-safe") {
            result.offset := 0
            result.length := 0
        }
    }

    // slither-disable-next-line write-after-write
    function emptyString() internal pure returns (string calldata result) {
        assembly ("memory-safe") {
            result.offset := 0
            result.length := 0
        }
    }
}
