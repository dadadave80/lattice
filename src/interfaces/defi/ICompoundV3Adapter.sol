// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICompoundV3Adapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Compound-v3-specific config ABI. The adapter also implements `IStrategy` +
///         `IProtocolAdapter`. Supply-only: no leverage, no oracle (1:1 base-asset accounting).
interface ICompoundV3Adapter {
    /// @notice Emitted once at init with the wiring.
    event CompoundV3AdapterConfigured(address indexed comet, address indexed asset, address indexed vault);

    /// @notice Emitted when the rewards controller is set.
    event CometRewardsSet(address indexed rewards);

    /// @notice The base asset reported by Comet does not match the configured asset.
    error CompoundV3AdapterBaseAssetMismatch(address cometBase, address configured);

    /// @notice Returns the Comet market this adapter supplies to.
    function comet() external view returns (address);

    /// @notice Returns the vault funds are returned to.
    function vault() external view returns (address);

    /// @notice Returns the Comet rewards controller.
    function cometRewards() external view returns (address);

    /// @notice Sets the Comet rewards controller (admin only).
    function setCometRewards(address rewards) external;

    /// @notice Sets the reward recipient (admin only).
    function setRewardRecipient(address recipient) external;
}
