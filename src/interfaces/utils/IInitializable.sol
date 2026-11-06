// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IInitializable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Solady (https://github.com/vectorized/solady/blob/main/src/utils/Initializable.sol)
/// @notice ABI declarations for initialization guards and their assembly-emitted event.
/// @dev No external functions or ERC-165 registration: this interface's id would be zero.
interface IInitializable {
    error InvalidInitialization();
    error NotInitializing();

    event Initialized(uint64 version);
}
