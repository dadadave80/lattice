// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Transient execution lock, not persistent storage.
/// `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC3643Execution")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC3643_EXECUTION_SLOT = 0x7ec596ba3a239053ac1cb6c6ad11931467488f3fa0022f65c88f71add3b23800;

error ERC3643ExecutionInProgress();

/// @title ERC3643ExecutionLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice One concrete native lock shared by the ERC-3643 suite's mutable entrypoints.
/// @dev Internal co-located calls use reviewed internal helpers under the already-held lock.
///      This is not an authority/bypass context and no public unchecked entrypoint is exported.
library ERC3643ExecutionLib {
    function enter() internal {
        checkIdle();
        assembly ("memory-safe") { tstore(ERC3643_EXECUTION_SLOT, 1) }
    }

    function exit() internal {
        assembly ("memory-safe") { tstore(ERC3643_EXECUTION_SLOT, 0) }
    }

    function checkIdle() internal view {
        bool busy;
        assembly ("memory-safe") { busy := tload(ERC3643_EXECUTION_SLOT) }
        if (busy) revert ERC3643ExecutionInProgress();
    }
}
