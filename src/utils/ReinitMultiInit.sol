// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AddressAndCalldataLengthMismatch} from "@diamond/initializers/MultiInit.sol";
import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";

/// @title ReinitMultiInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Runs ordered module initializers in a new, strictly increasing initialization window.
/// @dev Delegatecall from an authorized diamondCut; never install this helper as a facet.
///      Like MultiInit, a zero target terminates the batch. Successful empty/terminated batches advance the version.
/// @custom:lattice-kind bundle
contract ReinitMultiInit is Initializable {
    /// @param version Strictly greater than the diamond's current initialization version.
    /// @param inits Ordered delegatecall targets; zero terminates the batch.
    /// @param calldatas Calldata for each target, with the same length as inits.
    /// @custom:lattice-initializes caller-defined;
    /// @custom:lattice-after Initializable hard strictly-increasing-version;
    /// @custom:lattice-same-call none;
    /// @custom:lattice-sequence caller-defined;
    /// @custom:lattice-param version rule=strictly-increasing-uint64;
    /// @custom:lattice-param inits rule=ordered-code-bearing-addresses-zero-terminates;
    /// @custom:lattice-param calldatas rule=length-matches-inits;
    function reinitMulti(uint64 version, address[] calldata inits, bytes[] calldata calldatas)
        external
        reinitializer(version)
    {
        if (inits.length != calldatas.length) revert AddressAndCalldataLengthMismatch();
        for (uint256 i; i < inits.length; ++i) {
            if (inits[i] == address(0)) return;
            DiamondLib.initializeDiamondCut(inits[i], calldatas[i]);
        }
    }
}
