// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC4626Adapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Config ABI for the ERC4626-wrap adapter (Yearn v3 / MetaMorpho / any ERC4626). The
///         adapter also implements `IStrategy` + `IProtocolAdapter`. NAV via `convertToAssets`
///         (no oracle); supply-only (no leverage).
interface IERC4626Adapter {
    /// @notice Emitted once at init with the wiring.
    event ERC4626AdapterConfigured(address indexed targetVault, address indexed asset, address indexed vault);

    /// @dev The reward recipient is set via `IProtocolAdapter.RewardRecipientSet` (shared with the
    ///      generic adapter ABI) — not redeclared here to avoid an event-name collision when the
    ///      facet inherits both interfaces.

    /// @notice The target ERC4626 vault's asset does not match the configured asset.
    error ERC4626AdapterAssetMismatch(address targetAsset, address configured);

    /// @notice Returns the target ERC4626 vault this adapter deposits into.
    function targetVault() external view returns (address);

    /// @notice Returns the Lattice vault funds are returned to.
    function vault() external view returns (address);

    /// @notice Optional side-reward token (address(0) if none). Forwarded raw on harvest().
    function sideRewardToken() external view returns (address);

    /// @notice Sets an optional side-reward token to forward on harvest (admin only).
    function setSideRewardToken(address token) external;

    /// @notice Sets the reward recipient (admin only).
    function setRewardRecipient(address recipient) external;
}
