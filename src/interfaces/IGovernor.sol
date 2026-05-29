// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IGovernor
/// @notice Interface for the Governor module, implementing on-chain governance with
///         proposal lifecycle, voting, quorum, and optional TimelockController integration.
/// @dev Mirrors the OpenZeppelin v5 Governor interface combined with GovernorSettings,
///      GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction, and
///      GovernorTimelockControl extensions in a single monolithic interface.
interface IGovernor {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  ENUMS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The lifecycle state of a proposal.
    /// @dev Pending=0, Active=1, Canceled=2, Defeated=3, Succeeded=4, Queued=5, Expired=6, Executed=7
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    /// @notice The type of vote cast by a voter.
    /// @dev Against=0, For=1, Abstain=2 (Bravo counting)
    enum VoteType {
        Against,
        For,
        Abstain
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Emitted when a new proposal is created.
    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 voteStart,
        uint256 voteEnd,
        string description
    );

    /// @dev Emitted when a proposal is queued in the timelock.
    event ProposalQueued(uint256 proposalId, uint256 etaSeconds);

    /// @dev Emitted when a proposal is executed.
    event ProposalExecuted(uint256 proposalId);

    /// @dev Emitted when a proposal is canceled.
    event ProposalCanceled(uint256 proposalId);

    /// @dev Emitted when a vote is cast (without extra params).
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);

    /// @dev Emitted when a vote is cast with extra params.
    event VoteCastWithParams(
        address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason, bytes params
    );

    /// @dev Emitted when the voting delay is updated.
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);

    /// @dev Emitted when the voting period is updated.
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);

    /// @dev Emitted when the proposal threshold is updated.
    event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);

    /// @dev Emitted when the quorum numerator is updated.
    event QuorumNumeratorUpdated(uint256 oldNumerator, uint256 newNumerator);

    /// @dev Emitted when the timelock controller address is updated.
    event TimelockChange(address indexed oldTimelock, address indexed newTimelock);

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Thrown when a voter has already cast a vote on a proposal.
    error GovernorAlreadyCastVote(address voter);

    /// @dev Thrown when a deposit-based action is attempted but deposits are disabled.
    error GovernorDisabledDeposit();

    /// @dev Thrown when a caller is not the executor (address(this) for direct execution).
    error GovernorOnlyExecutor(address account);

    /// @dev Thrown when a proposal does not exist.
    error GovernorNonexistentProposal(uint256 proposalId);

    /// @dev Thrown when a proposal is in an unexpected state for the requested action.
    error GovernorUnexpectedProposalState(uint256 proposalId, ProposalState current, bytes32 expectedStates);

    /// @dev Thrown when the voting period is zero or otherwise invalid.
    error GovernorInvalidVotingPeriod(uint256 votingPeriod);

    /// @dev Thrown when the proposer lacks sufficient voting power.
    error GovernorInsufficientProposerVotes(address proposer, uint256 votes, uint256 threshold);

    /// @dev Thrown when proposal arrays (targets, calldatas, values) have mismatched lengths.
    error GovernorInvalidProposalLength(uint256 targets, uint256 calldatas, uint256 values);

    /// @dev Thrown when a proposal is already queued in the timelock.
    error GovernorAlreadyQueuedProposal(uint256 proposalId);

    /// @dev Thrown when a proposal is not queued but execution expects it to be.
    error GovernorNotQueuedProposal(uint256 proposalId);

    /// @dev Thrown when queue() is called but no timelock is configured.
    error GovernorQueueNotImplemented();

    /// @dev Thrown when the quorum numerator exceeds the denominator.
    error GovernorInvalidQuorumFraction(uint256 quorumNumerator, uint256 quorumDenominator);

    /// @dev Thrown when an EIP-712 signature is invalid for the expected voter.
    error GovernorInvalidSignature(address voter);

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The human-readable name of this governor.
    function name() external view returns (string memory);

    /// @notice The version string ("1").
    function version() external view returns (string memory);

    /// @notice The IVotes token used for voting power.
    function token() external view returns (address);

    /// @notice The current clock value (block.timestamp in uint48).
    function clock() external view returns (uint48);

    /// @notice Machine-readable clock mode string.
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external view returns (string memory);

    /// @notice Machine-readable counting mode string.
    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() external view returns (string memory);

    /// @notice Delay (in clock units) between proposal creation and the start of voting.
    function votingDelay() external view returns (uint256);

    /// @notice Duration (in clock units) of the voting period.
    function votingPeriod() external view returns (uint256);

    /// @notice Minimum voting power required to create a proposal.
    function proposalThreshold() external view returns (uint256);

    /// @notice The quorum required at a given timepoint (in token units).
    function quorum(uint256 timepoint) external view returns (uint256);

    /// @notice The current quorum numerator (out of quorumDenominator).
    function quorumNumerator() external view returns (uint256);

    /// @notice The quorum numerator at a given timepoint (historical or current).
    function quorumNumerator(uint256 timepoint) external view returns (uint256);

    /// @notice The quorum denominator (100 for percentage-based quorum).
    function quorumDenominator() external view returns (uint256);

    /// @notice The configured TimelockController address (address(0) if none).
    function timelock() external view returns (address);

    /// @notice Returns the current state of a proposal.
    function state(uint256 proposalId) external view returns (ProposalState);

    /// @notice The clock value at which voting starts for a proposal.
    function proposalSnapshot(uint256 proposalId) external view returns (uint256);

    /// @notice The clock value at which voting ends for a proposal.
    function proposalDeadline(uint256 proposalId) external view returns (uint256);

    /// @notice The address that created a proposal.
    function proposalProposer(uint256 proposalId) external view returns (address);

    /// @notice The timelock ETA (in seconds) for a queued proposal (0 if not queued).
    function proposalEta(uint256 proposalId) external view returns (uint256);

    /// @notice Returns the vote totals for a proposal.
    function proposalVotes(uint256 proposalId)
        external
        view
        returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes);

    /// @notice Returns whether an account has voted on a proposal.
    function hasVoted(uint256 proposalId, address account) external view returns (bool);

    /// @notice Returns the voting power of an account at a past timepoint.
    function getVotes(address account, uint256 timepoint) external view returns (uint256);

    /// @notice Computes the proposal ID for a given set of actions and description.
    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external pure returns (uint256);

    //*//////////////////////////////////////////////////////////////////////////
    //                            MUTATING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Create a new proposal.
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);

    /// @notice Queue a succeeded proposal in the timelock.
    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (uint256);

    /// @notice Execute a succeeded (or queued+ready) proposal.
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external payable returns (uint256);

    /// @notice Cancel a pending proposal (proposer only).
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external returns (uint256);

    /// @notice Cast a vote on an active proposal.
    function castVote(uint256 proposalId, uint8 support) external returns (uint256);

    /// @notice Cast a vote with a reason string.
    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external returns (uint256);

    /// @notice Cast a vote via an EIP-712 signature.
    function castVoteBySig(uint256 proposalId, uint8 support, address voter, bytes memory signature)
        external
        returns (uint256);

    //*//////////////////////////////////////////////////////////////////////////
    //                             ADMIN SETTERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Update the voting delay. Must be called via governance (address(this)).
    function setVotingDelay(uint48 newVotingDelay) external;

    /// @notice Update the voting period. Must be called via governance (address(this)).
    function setVotingPeriod(uint32 newVotingPeriod) external;

    /// @notice Update the proposal threshold. Must be called via governance (address(this)).
    function setProposalThreshold(uint256 newProposalThreshold) external;

    /// @notice Update the quorum numerator. Must be called via governance (address(this)).
    function updateQuorumNumerator(uint256 newQuorumNumerator) external;

    /// @notice Update the timelock address. Must be called via governance (address(this)).
    function updateTimelock(address newTimelock) external;
}
