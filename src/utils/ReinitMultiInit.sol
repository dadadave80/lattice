// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    AddressAndCalldataLengthMismatch,
    MultiInit__StepFailed,
    MultiInit__ZeroInit,
    NoBytecodeAtAddress
} from "@diamond/initializers/MultiInit.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";

/// @title ReinitMultiInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Runs ordered module initializers in a new, strictly increasing initialization window.
/// @dev Delegatecall from an authorized diamondCut; never install this helper as a facet.
///      Like MultiInit, zero targets are invalid and failures retain their step index and inner revert bytes.
///      A successful empty batch advances the version.
/// @custom:lattice-kind bundle
contract ReinitMultiInit is Initializable {
    /// @param version Strictly greater than the diamond's current initialization version.
    /// @param inits Ordered nonzero delegatecall targets, each with bytecode.
    /// @param calldatas Calldata for each target, with the same length as inits.
    /// @custom:lattice-initializes caller-defined;
    /// @custom:lattice-after Initializable hard strictly-increasing-version;
    /// @custom:lattice-same-call none;
    /// @custom:lattice-sequence caller-defined;
    /// @custom:lattice-param version rule=strictly-increasing-uint64;
    /// @custom:lattice-param inits rule=ordered-code-bearing-nonzero-addresses;
    /// @custom:lattice-param calldatas rule=length-matches-inits;
    function reinitMulti(uint64 version, address[] calldata inits, bytes[] calldata calldatas)
        external
        reinitializer(version)
    {
        if (inits.length != calldatas.length) revert AddressAndCalldataLengthMismatch();
        for (uint256 i; i < inits.length; ++i) {
            address target = inits[i];
            if (target == address(0)) revert MultiInit__ZeroInit(i);
            if (target.code.length == 0) revert NoBytecodeAtAddress(i, target);
            (bool success, bytes memory reason) = target.delegatecall(calldatas[i]);
            if (!success) revert MultiInit__StepFailed(i, target, reason);
        }
    }
}
