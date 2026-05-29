// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GovernorLib} from "@lattice/governance/libraries/GovernorLib.sol";
import {IGovernor} from "@lattice/interfaces/IGovernor.sol";

/// @title Governor
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Diamond-compatible stateless facet that delegates all governance logic to
///         {GovernorLib}. No state is held here — all state lives in ERC-7201 namespaced
///         storage accessed through the library.
/// @dev Consumers targeting a Diamond proxy should deploy this as a facet and call
///      {GovernorLib.__Governor_init} (wrapped in pre/postInitializer) from the diamond's
///      initializer. For standalone deployment use {GovernorStandalone}.
contract Governor is IGovernor {
    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IGovernor
    function name() external view virtual override returns (string memory) {
        return GovernorLib.name();
    }

    /// @inheritdoc IGovernor
    function version() external pure virtual override returns (string memory) {
        return GovernorLib.version();
    }

    /// @inheritdoc IGovernor
    function token() external view virtual override returns (address) {
        return GovernorLib.token();
    }

    /// @inheritdoc IGovernor
    function clock() external view virtual override returns (uint48) {
        return GovernorLib.clock();
    }

    /// @inheritdoc IGovernor
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external view virtual override returns (string memory) {
        return GovernorLib.CLOCK_MODE();
    }

    /// @inheritdoc IGovernor
    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() external pure virtual override returns (string memory) {
        return GovernorLib.COUNTING_MODE();
    }

    /// @inheritdoc IGovernor
    function votingDelay() external view virtual override returns (uint256) {
        return GovernorLib.votingDelay();
    }

    /// @inheritdoc IGovernor
    function votingPeriod() external view virtual override returns (uint256) {
        return GovernorLib.votingPeriod();
    }

    /// @inheritdoc IGovernor
    function proposalThreshold() external view virtual override returns (uint256) {
        return GovernorLib.proposalThreshold();
    }

    /// @inheritdoc IGovernor
    function quorum(uint256 timepoint) external view virtual override returns (uint256) {
        return GovernorLib.quorum(timepoint);
    }

    /// @inheritdoc IGovernor
    function quorumNumerator() external view virtual override returns (uint256) {
        return GovernorLib.quorumNumerator();
    }

    /// @inheritdoc IGovernor
    function quorumNumerator(uint256 timepoint) external view virtual override returns (uint256) {
        return GovernorLib.quorumNumeratorAt(timepoint);
    }

    /// @inheritdoc IGovernor
    function quorumDenominator() external pure virtual override returns (uint256) {
        return GovernorLib.quorumDenominator();
    }

    /// @inheritdoc IGovernor
    function timelock() external view virtual override returns (address) {
        return GovernorLib.timelock();
    }

    /// @inheritdoc IGovernor
    function state(uint256 proposalId) external view virtual override returns (ProposalState) {
        return GovernorLib.state(proposalId);
    }

    /// @inheritdoc IGovernor
    function proposalSnapshot(uint256 proposalId) external view virtual override returns (uint256) {
        return GovernorLib.proposalSnapshot(proposalId);
    }

    /// @inheritdoc IGovernor
    function proposalDeadline(uint256 proposalId) external view virtual override returns (uint256) {
        return GovernorLib.proposalDeadline(proposalId);
    }

    /// @inheritdoc IGovernor
    function proposalProposer(uint256 proposalId) external view virtual override returns (address) {
        return GovernorLib.proposalProposer(proposalId);
    }

    /// @inheritdoc IGovernor
    function proposalEta(uint256 proposalId) external view virtual override returns (uint256) {
        return GovernorLib.proposalEta(proposalId);
    }

    /// @inheritdoc IGovernor
    function proposalVotes(uint256 proposalId)
        external
        view
        virtual
        override
        returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)
    {
        return GovernorLib.proposalVotes(proposalId);
    }

    /// @inheritdoc IGovernor
    function hasVoted(uint256 proposalId, address account) external view virtual override returns (bool) {
        return GovernorLib.hasVoted(proposalId, account);
    }

    /// @inheritdoc IGovernor
    function getVotes(address account, uint256 timepoint) external view virtual override returns (uint256) {
        return GovernorLib.getVotes(account, timepoint);
    }

    /// @inheritdoc IGovernor
    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external pure virtual override returns (uint256) {
        return GovernorLib.hashProposal(targets, values, calldatas, descriptionHash);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            MUTATING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IGovernor
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external virtual override returns (uint256) {
        return GovernorLib.propose(targets, values, calldatas, description);
    }

    /// @inheritdoc IGovernor
    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external virtual override returns (uint256) {
        return GovernorLib.queue(targets, values, calldatas, descriptionHash);
    }

    /// @inheritdoc IGovernor
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external payable virtual override returns (uint256) {
        return GovernorLib.execute(targets, values, calldatas, descriptionHash);
    }

    /// @inheritdoc IGovernor
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external virtual override returns (uint256) {
        return GovernorLib.cancel(targets, values, calldatas, descriptionHash);
    }

    /// @inheritdoc IGovernor
    function castVote(uint256 proposalId, uint8 support) external virtual override returns (uint256) {
        return GovernorLib.castVote(proposalId, support);
    }

    /// @inheritdoc IGovernor
    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason)
        external
        virtual
        override
        returns (uint256)
    {
        return GovernorLib.castVoteWithReason(proposalId, support, reason);
    }

    /// @inheritdoc IGovernor
    function castVoteBySig(uint256 proposalId, uint8 support, address voter, bytes memory signature)
        external
        virtual
        override
        returns (uint256)
    {
        return GovernorLib.castVoteBySig(proposalId, support, voter, signature);
    }

    /// @inheritdoc IGovernor
    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes calldata params
    ) external virtual override returns (uint256) {
        return GovernorLib.castVoteWithReasonAndParams(proposalId, support, reason, params);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ADMIN SETTERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IGovernor
    function setVotingDelay(uint48 newVotingDelay) external virtual override {
        GovernorLib.setVotingDelay(newVotingDelay);
    }

    /// @inheritdoc IGovernor
    function setVotingPeriod(uint32 newVotingPeriod) external virtual override {
        GovernorLib.setVotingPeriod(newVotingPeriod);
    }

    /// @inheritdoc IGovernor
    function setProposalThreshold(uint256 newProposalThreshold) external virtual override {
        GovernorLib.setProposalThreshold(newProposalThreshold);
    }

    /// @inheritdoc IGovernor
    function updateQuorumNumerator(uint256 newQuorumNumerator) external virtual override {
        GovernorLib.updateQuorumNumerator(newQuorumNumerator);
    }

    /// @inheritdoc IGovernor
    function updateTimelock(address newTimelock) external virtual override {
        GovernorLib.updateTimelock(newTimelock);
    }
}
