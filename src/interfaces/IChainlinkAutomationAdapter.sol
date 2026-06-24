// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IChainlinkAutomationAdapter
/// @notice Interface for the ChainlinkAutomationAdapter Diamond facet — Chainlink Automation (keepers),
///         consumer side.
/// @dev Implements the Chainlink `AutomationCompatibleInterface` consumer surface with a canonical
///      time-interval upkeep: {checkUpkeep} reports `true` once `interval` seconds have elapsed, and
///      {performUpkeep} (gated to the configured Automation forwarder) advances the counter and resets
///      the timer. The upkeep condition is re-validated inside {performUpkeep} — `performData` is never
///      trusted blindly.
///
///      DECISION (recorded): this ships the **consumer-side compatible facet only**. The optional
///      `AutomationRegistrar`/`AutomationRegistry` on-chain registration + LINK-funding surface is a
///      separate concern and intentionally left as a future follow-up.
interface IChainlinkAutomationAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the Automation configuration is updated.
    /// @param forwarder The Automation forwarder allowed to call `performUpkeep`.
    /// @param interval  The minimum seconds between upkeeps.
    event ChainlinkAutomationConfigSet(address forwarder, uint256 interval);

    /// @notice Emitted when an upkeep is performed.
    /// @param counter The new upkeep counter value.
    event UpkeepPerformed(uint256 counter);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice Automation has not been configured (forwarder address is zero).
    error ChainlinkAutomationNotConfigured();

    /// @notice `setConfig` was called with a zero forwarder or zero interval.
    error ChainlinkAutomationInvalidConfig();

    /// @notice `performUpkeep` was called by an address other than the configured forwarder.
    /// @param caller The unauthorised caller.
    error ChainlinkAutomationOnlyForwarder(address caller);

    /// @notice `performUpkeep` was called before the upkeep interval had elapsed.
    error ChainlinkAutomationConditionNotMet();

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice Returns the configured Automation forwarder.
    function getForwarder() external view returns (address);

    /// @notice Returns the configured upkeep interval (seconds).
    function getInterval() external view returns (uint256);

    /// @notice Returns the timestamp of the last performed upkeep.
    function getLastTimeStamp() external view returns (uint256);

    /// @notice Returns the number of upkeeps performed.
    function getCounter() external view returns (uint256);

    /// @notice Reports whether the upkeep should run.
    /// @dev Returns `true` once `interval` seconds have elapsed since the last upkeep. `performData`
    ///      echoes `checkData`.
    /// @param checkData Arbitrary data configured on the upkeep.
    /// @return upkeepNeeded True if `performUpkeep` should be called.
    /// @return performData  The data to pass to `performUpkeep`.
    function checkUpkeep(bytes calldata checkData) external view returns (bool upkeepNeeded, bytes memory performData);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Sets or replaces the Automation configuration and resets the upkeep timer.
    /// @dev Caller must hold `DEFAULT_ADMIN_ROLE`. Reverts `ChainlinkAutomationInvalidConfig` on a zero
    ///      forwarder or zero interval.
    /// @param forwarder The Automation forwarder allowed to call `performUpkeep`.
    /// @param interval  The minimum seconds between upkeeps.
    function setConfig(address forwarder, uint256 interval) external;

    // -------------------------------------------------------------------------
    //                                Operations
    // -------------------------------------------------------------------------

    /// @notice Performs the upkeep. Gated to the configured forwarder.
    /// @dev Re-validates that `interval` seconds have elapsed (reverts `ChainlinkAutomationConditionNotMet`
    ///      otherwise), advances the counter, resets the timer, and emits `UpkeepPerformed`.
    /// @param performData The data returned by `checkUpkeep` (unused by the reference upkeep).
    function performUpkeep(bytes calldata performData) external;
}
