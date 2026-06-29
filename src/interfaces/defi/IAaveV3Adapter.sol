// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAaveV3Adapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Aave-v3-specific configuration ABI for the Lattice Aave adapter. The adapter also
///         implements `IStrategy` (asset/totalAssetsManaged/withdraw) and `IProtocolAdapter`
///         (deploy/harvest/emergencyWithdraw/health views).
/// @dev Errors generic to all adapters live in `IProtocolAdapter`; only Aave-specific config
///      errors/events live here.
interface IAaveV3Adapter {
    // ------------------------------- Events ---------------------------------

    /// @notice Emitted once at init with the immutable-ish wiring (provider, asset, vault).
    event AaveV3AdapterConfigured(address indexed provider, address indexed asset, address indexed vault);

    /// @notice Emitted when the eMode category is changed.
    event EModeSet(uint8 categoryId);

    /// @notice Emitted when the minimum health factor floor is changed.
    event MinHealthFactorSet(uint256 minHealthFactorWad);

    /// @notice Emitted after a lever op (borrow `asset` then re-supply it).
    event Levered(uint256 borrowed);

    /// @notice Emitted after a delever op (withdraw collateral then repay debt).
    event Delevered(uint256 repaid);

    /// @notice Emitted when the Aave rewards controller is set.
    event RewardsControllerSet(address indexed controller);

    // ------------------------------- Errors ---------------------------------

    /// @notice The configured asset's reserve has no aToken (asset not listed on Aave).
    error AaveV3AdapterReserveNotListed(address asset);

    /// @notice A min-health-factor below 1e18 (== 1.0) was supplied; that permits instant liquidation.
    error AaveV3AdapterInvalidMinHealthFactor(uint256 supplied);

    /// @notice A lever amount of zero was requested.
    error AaveV3AdapterZeroLeverAmount();

    // ----------------------------- Config reads -----------------------------

    /// @notice Returns the Aave PoolAddressesProvider this adapter resolves the Pool from.
    function addressesProvider() external view returns (address);

    /// @notice Returns the live aToken for the configured asset (resolved via the provider).
    function aToken() external view returns (address);

    /// @notice Returns the vault this adapter returns withdrawn funds to.
    function vault() external view returns (address);

    /// @notice Returns the current eMode category id set on the Pool for this adapter.
    function eModeCategory() external view returns (uint8);

    /// @notice Returns the configured Aave rewards controller (address(0) if unset).
    function rewardsController() external view returns (address);

    // ---------------------------- Config writes -----------------------------

    /// @notice Sets the Aave eMode category (admin only). Used to enable correlated-asset looping.
    function setEMode(uint8 categoryId) external;

    /// @notice Sets the minimum health-factor floor in WAD (admin only). Must be >= 1e18.
    function setMinHealthFactor(uint256 minHealthFactorWad) external;

    /// @notice Sets the reward recipient (admin only).
    function setRewardRecipient(address recipient) external;

    /// @notice Sets the Aave rewards controller (admin only).
    function setRewardsController(address controller) external;

    // ------------------------------ Leverage --------------------------------

    /// @notice Borrows `borrowAmount` of the asset and re-supplies it, increasing leverage.
    /// @dev Reverts `ProtocolAdapterHealthFactorBreached` if the resulting HF < the floor.
    function lever(uint256 borrowAmount) external;

    /// @notice Withdraws `collateralToPull` of the asset from supply and repays that much debt,
    ///         decreasing leverage and restoring HF.
    /// @return repaid The amount of debt repaid.
    function delever(uint256 collateralToPull) external returns (uint256 repaid);
}
