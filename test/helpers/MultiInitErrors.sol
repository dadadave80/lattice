// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MultiInit, MultiInit__StepFailed} from "@diamond/initializers/MultiInit.sol";
import {Bytes} from "@lattice/utils/libraries/Bytes.sol";

/// @title MultiInitErrors
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Builds exact expected diagnostics from a typed batch input, never from an observed failure.
library MultiInitErrors {
    error InvalidBatchWitness();

    /// @dev The test fixes the expected index and complete inner reason; only its target is read from the input.
    function at(uint256 index, bytes memory batchCall, bytes memory inner) internal pure returns (bytes memory) {
        if (batchCall.length < 4 || bytes4(batchCall) != MultiInit.multiInit.selector) revert InvalidBatchWitness();
        (address[] memory inits, bytes[] memory calls) = abi.decode(Bytes.slice(batchCall, 4), (address[], bytes[]));
        if (inits.length != calls.length || index >= inits.length) revert InvalidBatchWitness();
        return abi.encodeWithSelector(MultiInit__StepFailed.selector, index, inits[index], inner);
    }
}
