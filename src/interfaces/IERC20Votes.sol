// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC20Votes
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Votes.sol)
/// @notice Extension interface for ERC-20 tokens with capped-supply voting power.
/// @dev Voting-related events and functions are in IVotes; ERC-20 events in IERC20.
///      This interface adds only the supply-cap error specific to the votes extension.
interface IERC20Votes {
    /// @notice Thrown when a mint would push the total supply above type(uint208).max.
    /// @param increasedSupply The supply that would result from the mint.
    /// @param cap             The maximum allowed supply (type(uint208).max).
    error ERC20ExceededSafeSupply(uint256 increasedSupply, uint256 cap);
}
