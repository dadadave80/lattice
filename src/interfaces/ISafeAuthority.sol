// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ISafeAuthority
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Shared Safe-multisig authority surface for the Safe-gated diamond-cut facets
///         ({SafeDiamondCut} and {GovernedSafeDiamondCut}): the authority errors/events plus the
///         self-administered Safe-rotation entry point and the `safe()` getter.
/// @dev The authority is a pinned Gnosis Safe address (an M-of-N smart-contract multisig). The Safe
///      collects owner signatures off-chain and verifies the threshold on-chain inside
///      `execTransaction`, then dispatches the call to the facet. The facet does NOT re-verify
///      signatures; it trusts solely that `msg.sender == the pinned Safe`. The Safe MUST invoke the
///      facet with `operation = Call` (NEVER DelegateCall) — a DelegateCall would run the facet's code
///      in the Safe's own context, where `msg.sender` is whoever called the Safe, defeating the gate.
///      This surface is intentionally SEPARATE from the cut ABI so the cut facet's advertised ERC-165
///      id can stay the canonical cut selector `0x1f931c1c` ({SafeDiamondCut}) while the timelocked
///      variant ({GovernedSafeDiamondCut}) can omit a synchronous cut entirely.
interface ISafeAuthority {
    /// @dev Emitted when the pinned Safe authority is rotated to a new Safe via `setSafe`.
    /// @param oldSafe The previously pinned Safe.
    /// @param newSafe The newly pinned Safe.
    event SafeRotated(address indexed oldSafe, address indexed newSafe);

    /// @dev Thrown when a caller other than the pinned Safe attempts a Safe-gated operation
    ///      (a cut, a schedule/execute/cancel, a freeze, or a rotation).
    /// @param caller The unauthorized caller.
    error SafeDiamondCutUnauthorized(address caller);

    /// @dev Thrown when the supplied Safe address is the zero address.
    error SafeDiamondCutZeroSafe();

    /// @dev Thrown when `minThreshold` is zero (a Safe gate with a zero threshold is meaningless).
    error SafeDiamondCutZeroThreshold();

    /// @dev Thrown when the supplied Safe's on-chain threshold is below the required minimum, i.e. the
    ///      pinned authority is not a sufficiently-protected multisig.
    /// @param threshold The Safe's reported `getThreshold()`.
    /// @param minThreshold The required minimum threshold.
    error SafeDiamondCutThresholdTooLow(uint256 threshold, uint256 minThreshold);

    /// @notice Rotates the pinned Safe authority to `_newSafe`. Self-administered: callable ONLY by the
    ///         current pinned Safe, so only the existing multisig can hand authority to its successor.
    ///         `_newSafe` is validated (non-zero, real Safe whose threshold is at least the minimum
    ///         meaningful threshold of 1). Emits {SafeRotated}.
    /// @param _newSafe The new Safe to pin as the cut authority.
    function setSafe(address _newSafe) external;

    /// @notice Returns the currently pinned Safe authority.
    /// @return The pinned Safe address.
    function safe() external view returns (address);
}
