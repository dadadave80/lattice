// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IProtocolAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Sidecar interface implemented by every Lattice protocol adapter alongside
///         `IStrategy`. Covers what `IStrategy` deliberately omits: sweeping pushed idle
///         funds into the protocol (`deploy`), claiming and forwarding rewards raw
///         (`harvest`), emergency exit, and pause/health introspection.
/// @dev Adapters are stateless Diamond facets; all logic lives in their library + the
///      shared `AdapterBaseLib`. Errors are declared here (interface-owned) per Lattice
///      convention. Wide pragma so older-compiler consumers can import the ABI.
interface IProtocolAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when idle funds are swept into the protocol.
    /// @param asset  The underlying asset deployed.
    /// @param amount The amount deployed.
    event Deployed(address indexed asset, uint256 amount);

    /// @notice Emitted when reward tokens are claimed and forwarded raw to the recipient.
    /// @param rewardToken The reward token forwarded.
    /// @param recipient   The configured reward recipient.
    /// @param amount      The amount forwarded (post-transfer real delta).
    event RewardsForwarded(address indexed rewardToken, address indexed recipient, uint256 amount);

    /// @notice Emitted when the reward recipient is set or changed.
    event RewardRecipientSet(address indexed recipient);

    /// @notice Emitted when the adapter fully exits its position in an emergency.
    /// @param asset      The underlying asset recovered.
    /// @param toVault    The vault the funds were returned to.
    /// @param recovered  The amount returned to the vault.
    event EmergencyWithdrawn(address indexed asset, address indexed toVault, uint256 recovered);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice An operation requiring an active position was attempted while paused/stopped,
    ///         or the external protocol reports paused/frozen.
    error ProtocolAdapterPaused();

    /// @notice A zero address was supplied where a non-zero address is required.
    error ProtocolAdapterZeroAddress();

    /// @notice `deploy()` was called with no idle balance to sweep.
    error ProtocolAdapterNothingToDeploy();

    /// @notice A lever/delever/deploy op would push the position below the configured
    ///         minimum health factor.
    /// @param resulting The health factor (WAD) the op would produce.
    /// @param floor     The configured minimum health factor (WAD).
    error ProtocolAdapterHealthFactorBreached(uint256 resulting, uint256 floor);

    /// @notice A reward token transfer to the recipient failed.
    error ProtocolAdapterRewardForwardFailed(address rewardToken);

    /// @notice Caller is not authorized for this operation.
    error ProtocolAdapterUnauthorized(address caller);

    // -------------------------------------------------------------------------
    //                            Lifecycle (sidecar)
    // -------------------------------------------------------------------------

    /// @notice Sweeps the adapter's idle asset balance into the external protocol.
    /// @dev Required because the vault PUSHES funds via a bare ERC-20 transfer (no callback).
    ///      Reverts `ProtocolAdapterNothingToDeploy` if the idle balance is zero.
    /// @return deployed The amount swept into the protocol.
    function deploy() external returns (uint256 deployed);

    /// @notice Claims reward tokens from the protocol and forwards them RAW (no swap) to the
    ///         configured recipient.
    /// @dev Safe against zero-claim and fee-on-transfer reward tokens; never reverts `withdraw`.
    function harvest() external;

    /// @notice Fully exits the protocol position and returns all recovered assets to the vault.
    /// @dev Intended for the emergency path; callable by an authorized guardian/admin even when
    ///      the adapter is paused.
    /// @return recovered The amount returned to the vault.
    function emergencyWithdraw() external returns (uint256 recovered);

    // -------------------------------------------------------------------------
    //                              Introspection
    // -------------------------------------------------------------------------

    /// @notice Returns true when the adapter is paused or emergency-stopped, or the external
    ///         protocol reports the asset paused/frozen. When true, `deploy()` must be a no-op
    ///         path (revert), so a paused protocol cannot brick `rebalance()`.
    function isPaused() external view returns (bool);

    /// @notice Returns the current health factor (WAD, 1e18 == 1.0) of the adapter's position.
    /// @dev Supply-only adapters return `type(uint256).max` (no debt). Leverage adapters return
    ///      collateralValue * liquidationThreshold / debtValue.
    function healthFactor() external view returns (uint256);

    /// @notice Returns the configured minimum health factor (WAD) the adapter must not breach.
    function minHealthFactor() external view returns (uint256);

    /// @notice Returns the address rewards are forwarded to.
    function rewardRecipient() external view returns (address);
}
