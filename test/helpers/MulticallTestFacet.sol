// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title MulticallTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet exposing the resolved caller (`msg.sender`) so the {Multicall} facet test can prove a
///         batched sub-call — dispatched as a `delegatecall` back through the diamond — sees the ORIGINAL outer
///         caller, not the diamond. Cut ON TOP of the production {DeployMulticall} recipe; never shipped, never
///         part of a `run()` deploy.
contract MulticallTestFacet {
    /// @notice Returns the caller resolved inside this facet (`msg.sender`) for test inspection.
    function currentSender() external view returns (address) {
        return msg.sender;
    }
}
