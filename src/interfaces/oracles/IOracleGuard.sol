// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IOracleGuard
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chainlink (https://docs.chain.link/data-feeds/l2-sequencer-feeds)
/// @notice Interface for the OracleGuard Diamond facet: an opt-in guarded price read layered over any Lattice
///         price adapter that exposes the {IPriceOracleReader} `latestAnswer(bytes32)` read. It adds the two
///         checks the adapters leave to the integrator: the Chainlink L2 sequencer-uptime feed (with a grace
///         period after a restart) and per-key `[min, max]` sanity bounds on the WAD answer.
/// @dev Integrators read prices through {guardedAnswer} instead of the adapter's `latestAnswer`. The guard
///      keeps its own storage and calls the configured oracle's `latestAnswer`, so the adapters' storage
///      and interfaceIds are untouched; every adapter check (staleness, round completeness, non-positive
///      answers) still runs, and its revert bubbles up unchanged. The oracle is either the guard's own
///      diamond (the guard cut next to the adapter, with `OracleGuardInit` run beside the adapter's init so
///      ERC-165 reports this interface) or another adapter diamond (the standalone `DeployOracleGuard` recipe).
///
///      Configuration is opt-in and fails closed once set:
///      - Sequencer check: skipped while the sequencer feed is `address(0)` (L1 deployments). Once set,
///        a read reverts unless the uptime feed answers `0` (up), its `startedAt` is non-zero (an Arbitrum
///        uptime feed that was never initialized reports `0`), and more than `gracePeriod` seconds have
///        passed since `startedAt`.
///      - Keys: an unconfigured key reverts {OracleGuardKeyNotConfigured} rather than passing a price
///        through unchecked.
///      - Bounds: `(0, 0)` disables the bounds of a key. Otherwise the WAD answer must lie in
///        `[minAnswer, maxAnswer]`. Bounds are never read from the aggregator, whose `minAnswer`/`maxAnswer`
///        most Chainlink feeds no longer use. A non-positive WAD answer always reverts, even with bounds
///        disabled.
interface IOracleGuard {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the sequencer-uptime configuration is set.
    /// @param sequencerFeed The Chainlink L2 sequencer-uptime feed (`address(0)` disables the check).
    /// @param gracePeriod   Seconds after a sequencer restart during which reads revert.
    event SequencerConfigSet(address indexed sequencerFeed, uint48 gracePeriod);

    /// @notice Emitted when a guarded key is configured or reconfigured.
    /// @param key       The feed identifier, shared with the oracle's `latestAnswer(key)`.
    /// @param oracle    The adapter (or adapter diamond) read for `key`.
    /// @param minAnswer Lowest accepted WAD answer.
    /// @param maxAnswer Highest accepted WAD answer (`(0, 0)` disables the bounds).
    event GuardedFeedSet(bytes32 indexed key, address oracle, int256 minAnswer, int256 maxAnswer);

    /// @notice Emitted when a guarded key is removed.
    /// @param key The removed feed identifier.
    event GuardedFeedRemoved(bytes32 indexed key);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The key has no guard configuration.
    /// @param key The feed identifier.
    error OracleGuardKeyNotConfigured(bytes32 key);

    /// @notice The uptime feed reports the sequencer down (`status != 0`) or uninitialized (`startedAt == 0`).
    /// @param status    The uptime feed's answer (`0` = up, `1` = down).
    /// @param startedAt The uptime feed's `startedAt`.
    error OracleGuardSequencerDown(int256 status, uint256 startedAt);

    /// @notice The sequencer came back up no more than `gracePeriod` seconds ago (or `startedAt` is in the future).
    /// @param startedAt   When the sequencer's current status began.
    /// @param gracePeriod The configured grace period in seconds.
    error OracleGuardGracePeriodNotOver(uint256 startedAt, uint256 gracePeriod);

    /// @notice The oracle returned a non-positive WAD answer.
    /// @param key       The feed identifier.
    /// @param answerWad The rejected answer.
    error OracleGuardInvalidAnswer(bytes32 key, int256 answerWad);

    /// @notice The WAD answer is outside the key's configured bounds.
    /// @param key       The feed identifier.
    /// @param answerWad The rejected answer.
    /// @param minAnswer The configured lower bound.
    /// @param maxAnswer The configured upper bound.
    error OracleGuardAnswerOutOfBounds(bytes32 key, int256 answerWad, int256 minAnswer, int256 maxAnswer);

    /// @notice A setter was called with an invalid parameter: a zero oracle, negative or inverted bounds, or a
    ///         sequencer feed with a zero grace period.
    error OracleGuardInvalidConfig();

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the oracle's WAD answer for `key` after the sequencer and bounds checks.
    /// @dev Reverts with the oracle's own error when its checks fail, and with this interface's errors when
    ///      the guard's checks fail.
    /// @param key The feed identifier.
    /// @return answerWad The checked price scaled to 1e18.
    function guardedAnswer(bytes32 key) external view returns (int256 answerWad);

    /// @notice Reverts unless the sequencer is up and past its grace period. No-op while no feed is set.
    /// @dev For integrators that read something other than {guardedAnswer} (raw reads, TWAPs) on an L2.
    function checkSequencerUptime() external view;

    /// @notice Returns the sequencer-uptime configuration.
    /// @return sequencerFeed The uptime feed (`address(0)` when the check is disabled).
    /// @return gracePeriod   The grace period in seconds.
    function getSequencerConfig() external view returns (address sequencerFeed, uint48 gracePeriod);

    /// @notice Returns the guard configuration of `key`.
    /// @param key The feed identifier.
    /// @return oracle    The oracle read for `key` (`address(0)` when unconfigured).
    /// @return minAnswer Lowest accepted WAD answer.
    /// @return maxAnswer Highest accepted WAD answer.
    function getGuardedFeed(bytes32 key) external view returns (address oracle, int256 minAnswer, int256 maxAnswer);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Sets the Chainlink L2 sequencer-uptime feed and the grace period after a restart.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. `sequencerFeed == address(0)` disables the check; a non-zero
    ///      feed requires a non-zero `gracePeriod` (Chainlink's example uses 3600 seconds).
    /// @param sequencerFeed The uptime feed for this chain.
    /// @param gracePeriod   Seconds after a restart during which reads revert.
    function setSequencerConfig(address sequencerFeed, uint48 gracePeriod) external;

    /// @notice Configures `key`: the oracle to read and the accepted WAD range.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. `oracle` must be non-zero. `(0, 0)` disables the bounds;
    ///      otherwise `0 <= minAnswer <= maxAnswer`.
    /// @param key       The feed identifier, passed through to the oracle's `latestAnswer(key)`.
    /// @param oracle    The adapter (or adapter diamond) to read; the guard's own diamond when co-cut.
    /// @param minAnswer Lowest accepted WAD answer.
    /// @param maxAnswer Highest accepted WAD answer.
    function setGuardedFeed(bytes32 key, address oracle, int256 minAnswer, int256 maxAnswer) external;

    /// @notice Removes the guard configuration of `key`; {guardedAnswer} then reverts for it.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`.
    /// @param key The feed identifier.
    function removeGuardedFeed(bytes32 key) external;
}
