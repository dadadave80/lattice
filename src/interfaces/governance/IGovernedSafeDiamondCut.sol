// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";

/// @title IGovernedSafeDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice External interface for the Safe-multisig-gated diamond-cut facet WITH a built-in timelock.
///         Cuts cannot be applied synchronously; they must first be `scheduleCut`-ed by the pinned Safe,
///         mature past a `minDelay`, and only then be `executeCut`-ed. A pending operation can be
///         `cancelCut`-ed by the Safe. This module deliberately does NOT expose `diamondCut` at the
///         canonical selector `0x1f931c1c` — every cut is delayed — so its scheduling surface forms a
///         genuinely new interface with its own ERC-165 id.
/// @dev The authority is a pinned Gnosis Safe address (an M-of-N smart-contract multisig). The Safe
///      collects owner signatures off-chain and verifies the threshold on-chain inside
///      `execTransaction`, then dispatches the schedule/execute/cancel call to this facet. The facet
///      does NOT re-verify signatures; it trusts solely that `msg.sender == the pinned Safe`. The Safe
///      MUST invoke this facet with `operation = Call` (NEVER DelegateCall) — a DelegateCall would run
///      this facet's code in the Safe's own context, where `msg.sender` is whoever called the Safe,
///      defeating the gate. An operation id is `keccak256(abi.encode(cuts, init, calldata, salt))`; the
///      `salt` lets the same cut payload be scheduled more than once over the diamond's lifetime.
interface IGovernedSafeDiamondCut {
    /// @dev Emitted when the pinned Safe schedules a cut. The operation becomes executable at `eta`.
    /// @param id The operation id `keccak256(abi.encode(cuts, init, calldata, salt))`.
    /// @param facetCutCount The number of FacetCut entries scheduled.
    /// @param init The init address that will be delegatecalled after the cut (address(0) if none).
    /// @param salt The caller-chosen salt disambiguating otherwise-identical payloads.
    /// @param eta The earliest `block.timestamp` at which the operation may be executed.
    event CutScheduled(bytes32 indexed id, uint256 facetCutCount, address indexed init, bytes32 salt, uint256 eta);

    /// @dev Emitted after a scheduled, matured cut is executed and applied.
    /// @param id The operation id that was executed.
    event CutExecuted(bytes32 indexed id);

    /// @dev Emitted when the pinned Safe cancels a still-pending operation.
    /// @param id The operation id that was cancelled.
    event CutCancelled(bytes32 indexed id);

    /// @dev Emitted when the minimum timelock delay is changed (self-administered, by the pinned Safe).
    /// @param oldDelay The previous minimum delay (seconds).
    /// @param newDelay The new minimum delay (seconds).
    event MinDelayChanged(uint256 oldDelay, uint256 newDelay);

    /// @dev Thrown when scheduling an operation id that is already scheduled (pending or matured).
    /// @param id The duplicate operation id.
    error CutAlreadyScheduled(bytes32 id);

    /// @dev Thrown when executing or cancelling an operation id that is not currently scheduled.
    /// @param id The unknown operation id.
    error CutNotScheduled(bytes32 id);

    /// @dev Thrown when executing an operation before its `eta` (timelock not yet elapsed).
    /// @param id The operation id.
    /// @param eta The earliest timestamp at which execution is permitted.
    error CutNotReady(bytes32 id, uint256 eta);

    /// @notice Schedules a cut for later execution. Gated to the pinned Safe and rejected while
    ///         emergency-stopped. Reverts {CutAlreadyScheduled} if the id is already pending.
    /// @param _diamondCut The facet addresses, cut actions, and function selectors.
    /// @param _init The address delegatecalled after the cut (address(0) to skip).
    /// @param _calldata The calldata passed to `_init`.
    /// @param _salt A caller-chosen salt disambiguating otherwise-identical payloads.
    /// @return id The operation id `keccak256(abi.encode(_diamondCut, _init, _calldata, _salt))`.
    function scheduleCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata, bytes32 _salt)
        external
        returns (bytes32 id);

    /// @notice Executes a previously-scheduled, matured cut. Gated to the pinned Safe and rejected while
    ///         emergency-stopped. Reverts {CutNotScheduled} if unknown, {CutNotReady} if before `eta`,
    ///         and the shared frozen-selector guard if a Replace/Remove touches a frozen selector. The
    ///         arguments must match those passed to `scheduleCut` exactly (they re-derive the id).
    /// @param _diamondCut The facet addresses, cut actions, and function selectors.
    /// @param _init The address delegatecalled after the cut (address(0) to skip).
    /// @param _calldata The calldata passed to `_init`.
    /// @param _salt The salt used at schedule time.
    function executeCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata, bytes32 _salt)
        external
        payable;

    /// @notice Cancels a still-pending operation. Gated to the pinned Safe. Reverts {CutNotScheduled}
    ///         if the id is not currently scheduled.
    /// @param _id The operation id to cancel.
    function cancelCut(bytes32 _id) external;

    /// @notice Returns the ready timestamp (`eta`) of an operation, or 0 if it is not scheduled.
    /// @param _id The operation id to query.
    /// @return The `eta`, or 0 if unknown/cancelled/executed.
    function getTimestamp(bytes32 _id) external view returns (uint256);

    /// @notice Returns whether `_id` is scheduled but not yet matured (eta in the future).
    /// @param _id The operation id to query.
    function isOperationPending(bytes32 _id) external view returns (bool);

    /// @notice Returns whether `_id` is scheduled and matured (eta reached, ready to execute).
    /// @param _id The operation id to query.
    function isOperationReady(bytes32 _id) external view returns (bool);

    /// @notice Returns whether `_id` has already been executed (and thereby cleared).
    /// @param _id The operation id to query.
    function isOperationDone(bytes32 _id) external view returns (bool);

    /// @notice Returns the minimum timelock delay (seconds) enforced between schedule and execute.
    function minDelay() external view returns (uint256);
}
