// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GovernorLib} from "@lattice/governance/libraries/GovernorLib.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";

/// @title Governor
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/Governor.sol)
/// @notice Diamond-compatible stateless facet that delegates all governance logic to
///         {GovernorLib}. No state is held here — all state lives in ERC-7201 namespaced
///         storage accessed through the library.
/// @dev Consumers targeting a Diamond proxy should deploy this as a facet and call
///      {GovernorLib.__Governor_init} (wrapped in pre/postInitializer) from the diamond's
///      initializer. For standalone deployment use {GovernorStandalone}.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
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
    function queue(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash)
        external
        virtual
        override
        returns (uint256)
    {
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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect Governor methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `CLOCK_MODE()` 0x4bf5d7e9
    ///      `COUNTING_MODE()` 0xdd4e2ba5
    ///      `cancel(address[],uint256[],bytes[],bytes32)` 0x452115d6
    ///      `castVote(uint256,uint8)` 0x56781388
    ///      `castVoteBySig(uint256,uint8,address,bytes)` 0x8ff262e3
    ///      `castVoteWithReason(uint256,uint8,string)` 0x7b3c71d3
    ///      `castVoteWithReasonAndParams(uint256,uint8,string,bytes)` 0x5f398a14
    ///      `clock()` 0x91ddadf4
    ///      `execute(address[],uint256[],bytes[],bytes32)` 0x2656227d
    ///      `getVotes(address,uint256)` 0xeb9019d4
    ///      `hasVoted(uint256,address)` 0x43859632
    ///      `hashProposal(address[],uint256[],bytes[],bytes32)` 0xc59057e4
    ///      `name()` 0x06fdde03
    ///      `proposalDeadline(uint256)` 0xc01f9e37
    ///      `proposalEta(uint256)` 0xab58fb8e
    ///      `proposalProposer(uint256)` 0x143489d0
    ///      `proposalSnapshot(uint256)` 0x2d63f693
    ///      `proposalThreshold()` 0xb58131b0
    ///      `proposalVotes(uint256)` 0x544ffc9c
    ///      `propose(address[],uint256[],bytes[],string)` 0x7d5e81e2
    ///      `queue(address[],uint256[],bytes[],bytes32)` 0x160cbed7
    ///      `quorum(uint256)` 0xf8ce560a
    ///      `quorumDenominator()` 0x97c3d334
    ///      `quorumNumerator()` 0xa7713a70
    ///      `quorumNumerator(uint256)` 0x60c4247f
    ///      `setProposalThreshold(uint256)` 0xece40cc1
    ///      `setVotingDelay(uint48)` 0x79051887
    ///      `setVotingPeriod(uint32)` 0xe540d01d
    ///      `state(uint256)` 0x3e4f49e6
    ///      `timelock()` 0xd33219b4
    ///      `token()` 0xfc0c546a
    ///      `updateQuorumNumerator(uint256)` 0x06f3f9e6
    ///      `updateTimelock(address)` 0xa890c910
    ///      `version()` 0x54fd4d50
    ///      `votingDelay()` 0x3932abb1
    ///      `votingPeriod()` 0x02a251a3
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
            hex"4bf5d7e9dd4e2ba5452115d6567813888ff262e37b3c71d35f398a1491ddadf42656227deb9019d443859632c59057e406fdde03c01f9e37ab58fb8e143489d02d63f693b58131b0544ffc9c7d5e81e2160cbed7f8ce560a97c3d334a7713a7060c4247fece40cc179051887e540d01d3e4f49e6d33219b4fc0c546a06f3f9e6a890c91054fd4d503932abb102a251a3";
    }
}
