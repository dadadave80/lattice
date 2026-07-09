// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {ISafeAuthority} from "@lattice/interfaces/governance/ISafeAuthority.sol";

/// @title ISafeDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice External interface for the instant (no-delay) Safe-multisig-gated diamond-cut facet. Exposes
///         the EIP-2535 `diamondCut` function at the canonical selector `0x1f931c1c` so it transparently
///         replaces diamond-lib's owner-gated `DiamondCutFacet` in a Safe-governed deployment. Inherits
///         the shared Safe-authority surface ({ISafeAuthority}: rotation, errors, events).
/// @dev The authority is a pinned Gnosis Safe address (an M-of-N smart-contract multisig). The Safe
///      collects owner signatures off-chain and verifies the threshold on-chain inside
///      `execTransaction`, then dispatches the cut to this facet. The facet does NOT re-verify
///      signatures; it trusts solely that `msg.sender == the pinned Safe`. The Safe MUST invoke this
///      facet with `operation = Call` (NEVER DelegateCall) — a DelegateCall would run this facet's code
///      in the Safe's own context, where `msg.sender` is whoever called the Safe, defeating the gate.
interface ISafeDiamondCut is ISafeAuthority {
    /// @dev Emitted after a Safe-authorized cut is applied. Mirrors that the guard (emergency-stop,
    ///      then `msg.sender == the pinned Safe`) passed before delegating to DiamondLib.
    /// @param safe The pinned Safe that authorized the cut (the caller).
    /// @param facetCutCount The number of FacetCut entries applied.
    /// @param init The init address delegatecalled after the cut (address(0) if none).
    event UpgradeExecuted(address indexed safe, uint256 facetCutCount, address indexed init);

    /// @notice Add/replace/remove any number of functions and optionally execute a function with
    ///         delegatecall — but only when not emergency-stopped and the caller is the pinned Safe.
    ///         The Safe MUST call with `operation = Call`.
    /// @param _diamondCut The facet addresses, cut actions, and function selectors.
    /// @param _init The address of the contract or facet to delegatecall after the cut (0 to skip).
    /// @param _calldata The calldata passed to `_init`.
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external payable;
}
