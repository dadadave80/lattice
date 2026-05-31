// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IVotes
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/utils/IVotes.sol)
/// @notice Standard voting-power interface (ERC-5805 + ERC-6372).
interface IVotes {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Emitted when an account changes its delegate.
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice Emitted when a token transfer or delegate change causes an account's voting weight to change.
    event DelegateVotesChanged(address indexed delegate, uint256 previousVotes, uint256 newVotes);

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The signature used for `delegateBySig` has expired.
    error VotesExpiredSignature(uint256 expiry);

    /// @notice The clock was changed in an inconsistent manner.
    error ERC6372InconsistentClock();

    /// @notice Attempted to look up a future timepoint.
    error ERC5805FutureLookup(uint256 timepoint, uint48 clock);

    //*//////////////////////////////////////////////////////////////////////////
    //                           VOTING POWER VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the current voting power of `account`.
    function getVotes(address account) external view returns (uint256);

    /// @notice Returns the voting power of `account` at `timepoint` (in the past).
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);

    /// @notice Returns the total token supply checkpointed at `timepoint` (in the past).
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);

    //*//////////////////////////////////////////////////////////////////////////
    //                           DELEGATION VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the current delegate of `account`.
    function delegates(address account) external view returns (address);

    //*//////////////////////////////////////////////////////////////////////////
    //                         DELEGATION MUTATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Delegates votes from the caller to `delegatee`.
    function delegate(address delegatee) external;

    /// @notice Delegates votes from the signer to `delegatee` via an EIP-712 signature.
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) external;

    //*//////////////////////////////////////////////////////////////////////////
    //                               CLOCK (ERC-6372)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the current timepoint (block timestamp or block number).
    function clock() external view returns (uint48);

    /// @notice Returns a machine-readable string describing the clock mode.
    /// @dev See ERC-6372 for defined values. Default is "mode=timestamp".
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external view returns (string memory);
}
