// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAutomationCompatible
/// @author Modified from Chainlink (https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol)
/// @notice Consumer-side interface for Chainlink Automation (keepers).
/// @dev Vendored — do not add a chainlink dependency. Automation nodes simulate `checkUpkeep`
///      off-chain; when it returns `true`, the Automation forwarder calls `performUpkeep`, which the
///      consumer must guard so only the registered forwarder may invoke it.
interface IAutomationCompatible {
    /// @notice Reports whether the upkeep should run, and the data to pass to `performUpkeep`.
    /// @param checkData    Arbitrary data configured on the upkeep at registration.
    /// @return upkeepNeeded True if `performUpkeep` should be called.
    /// @return performData  The data to pass to `performUpkeep`.
    function checkUpkeep(bytes calldata checkData) external returns (bool upkeepNeeded, bytes memory performData);

    /// @notice Performs the upkeep. Must be guarded to the Automation forwarder.
    /// @param performData The data returned by `checkUpkeep`.
    function performUpkeep(bytes calldata performData) external;
}
