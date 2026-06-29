// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IVestingWallet
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/finance/VestingWallet.sol)
/// @dev External interface of VestingWallet for ERC-165 detection and consumer ABI.
interface IVestingWallet {
    /// @dev Emitted when ETH is released to the beneficiary.
    /// @param amount The amount of ETH released (in wei).
    event EtherReleased(uint256 amount);

    /// @dev Emitted when an ERC20 token is released to the beneficiary.
    /// @param token The address of the ERC20 token contract.
    /// @param amount The amount of tokens released.
    event ERC20Released(address indexed token, uint256 amount);

    /// @notice ERC20 transfer to the beneficiary failed.
    /// @param token The token whose transfer failed.
    error VestingWalletTransferFailed(address token);

    /// @notice Returns the start timestamp of the vesting schedule.
    /// @return The Unix timestamp at which vesting begins.
    function start() external view returns (uint256);

    /// @notice Returns the duration of the vesting schedule in seconds.
    /// @return The total duration of the vesting period.
    function duration() external view returns (uint256);

    /// @notice Returns the end timestamp of the vesting schedule.
    /// @return The Unix timestamp at which vesting completes (start + duration).
    function end() external view returns (uint256);

    /// @notice Returns the total amount of ETH already released.
    /// @return The cumulative ETH released to the beneficiary.
    function released() external view returns (uint256);

    /// @notice Returns the total amount of a specific ERC20 token already released.
    /// @param token The ERC20 token contract address.
    /// @return The cumulative token amount released to the beneficiary.
    function released(address token) external view returns (uint256);

    /// @notice Returns the amount of ETH that can currently be released.
    /// @return The releasable ETH amount (vested minus already released).
    function releasable() external view returns (uint256);

    /// @notice Returns the amount of a specific ERC20 token that can currently be released.
    /// @param token The ERC20 token contract address.
    /// @return The releasable token amount (vested minus already released).
    function releasable(address token) external view returns (uint256);

    /// @notice Calculates the vested ETH amount at a given timestamp.
    /// @param timestamp The Unix timestamp to evaluate the vesting schedule at.
    /// @return The total ETH that would be vested at the given timestamp.
    function vestedAmount(uint64 timestamp) external view returns (uint256);

    /// @notice Calculates the vested ERC20 token amount at a given timestamp.
    /// @param token The ERC20 token contract address.
    /// @param timestamp The Unix timestamp to evaluate the vesting schedule at.
    /// @return The total token amount that would be vested at the given timestamp.
    function vestedAmount(address token, uint64 timestamp) external view returns (uint256);

    /// @notice Releases all currently releasable ETH to the beneficiary.
    /// @dev Anyone may call this; funds always go to the beneficiary (owner).
    /// Emits an {EtherReleased} event.
    function release() external;

    /// @notice Releases all currently releasable tokens of a specific ERC20 to the beneficiary.
    /// @param token The ERC20 token contract address to release.
    /// @dev Anyone may call this; funds always go to the beneficiary (owner).
    /// Emits an {ERC20Released} event.
    function release(address token) external;
}
