// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GelatoAutomateAdapterLib} from "@lattice/oracles/libraries/GelatoAutomateAdapterLib.sol";

/// @title GelatoAutomateAdapterTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet exposing the internal {GelatoAutomateAdapterLib.requireDedicatedMsgSender} exec guard
///         the production {GelatoAutomateAdapter} facet does not surface (it is meant to gate a consumer's
///         app-specific exec entrypoint). Cut ON TOP of the production {DeployGelatoAutomateAdapter} recipe so a
///         facet test can prove Gelato's dedicated-msg.sender gate blocks a real exec through the REAL diamond
///         dispatch — never shipped, never part of a `run()` deploy.
contract GelatoAutomateAdapterTestFacet {
    /// @notice Guarded exec entrypoint that reverts (`GelatoAutomateOnlyDedicatedMsgSender`) unless the caller is
    ///         the configured dedicated msg.sender.
    function exec() external view {
        GelatoAutomateAdapterLib.requireDedicatedMsgSender();
    }
}
