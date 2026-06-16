// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title GovernanceStackTest
/// @notice Integration test for the full governance stack:
///         ERC20Votes token + TimelockController + Governor
///
/// End-to-end flows tested:
///  1. Mint voting tokens, delegates, propose, vote, queue, execute.
///  2. Cancel mid-flight: proposer cancels an Active proposal; also tested
///     for Queued state where the timelock op is also canceled.
///
/// @dev Uses GovernorStandalone and TimelockControllerStandalone (same setup
///      as the unit test) rather than building a custom Diamond, which mirrors
///      real consumer deployments. A MockGovTarget records the call result.

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernorStandalone} from "@lattice/governance/GovernorStandalone.sol";
import {TimelockControllerStandalone} from "@lattice/governance/TimelockControllerStandalone.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {IGovernor} from "@lattice/interfaces/IGovernor.sol";
import {ITimelockController} from "@lattice/interfaces/ITimelockController.sol";
import {ERC20Votes} from "@lattice/tokens/ERC20Votes.sol";
import {ERC20Lib} from "@lattice/tokens/libraries/ERC20Lib.sol";
import {ERC20VotesLib} from "@lattice/tokens/libraries/ERC20VotesLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                             MOCK CONTRACTS
//////////////////////////////////////////////////////////////////////////*//

/// @notice ERC20Votes token for governance.
contract GovStackToken is ERC20Votes {
    function initialize(string memory name_, string memory symbol_, address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init(name_, symbol_);
        EIP712Lib.__EIP712_init(name_, "1");
        NoncesLib.__Nonces_init();
        VotesLib.__Votes_init();
        ERC20VotesLib.__ERC20Votes_init();
        AccessControlLib.__AccessControl_init(admin_);
        InitializableLib.postInitializer(s);
    }

    function mint(address to, uint256 amount) external {
        ERC20VotesLib._mint(to, amount);
    }
}

/// @notice Records external calls made by the governor during execution.
contract MockGovTarget {
    uint256 public value;
    bool public called;

    function setValue(uint256 _value) external {
        value = _value;
        called = true;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                              TEST SUITE
//////////////////////////////////////////////////////////////////////////*//

contract GovernanceStackTest is Test {
    GovStackToken token;
    TimelockControllerStandalone timelock;
    GovernorStandalone governor;
    MockGovTarget govTarget;

    address admin = address(0xAD);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address stranger = address(0x5);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    uint48 constant VOTING_DELAY = 1 days;
    uint32 constant VOTING_PERIOD = 7 days;
    uint256 constant PROPOSAL_THRESHOLD = 1_000e18;
    uint256 constant QUORUM_NUMERATOR = 4; // 4 %
    uint256 constant TIMELOCK_DELAY = 2 days;

    // ---- re-declare events needed for vm.expectEmit ----
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
    event ProposalQueued(uint256 proposalId, uint256 etaSeconds);
    event ProposalExecuted(uint256 proposalId);
    event ProposalCanceled(uint256 proposalId);
    event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason);

    function setUp() public {
        vm.warp(1_000_000);

        // 1. Deploy token and mint to voters.
        token = new GovStackToken();
        token.initialize("Governance Token", "GOV", admin);

        token.mint(alice, INITIAL_SUPPLY);
        token.mint(bob, INITIAL_SUPPLY);

        // 2. Both delegate to themselves.
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);

        // Checkpoint delegation block.
        vm.warp(block.timestamp + 1);

        // 3. Deploy timelock.
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open execution
        timelock = new TimelockControllerStandalone(TIMELOCK_DELAY, proposers, executors, admin);

        // 4. Deploy governor.
        GovernorStandalone.Config memory cfg = GovernorStandalone.Config({
            name: "Stack Governor",
            token: address(token),
            timelock: address(timelock),
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            proposalThreshold: PROPOSAL_THRESHOLD,
            quorumNumerator: QUORUM_NUMERATOR
        });
        governor = new GovernorStandalone(cfg);

        // Grant governor PROPOSER + CANCELLER roles on timelock.
        vm.startPrank(admin);
        timelock.grantRole(TimelockControllerLib.PROPOSER_ROLE, address(governor));
        timelock.grantRole(TimelockControllerLib.CANCELLER_ROLE, address(governor));
        vm.stopPrank();

        govTarget = new MockGovTarget();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    function _buildProposal()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](1);
        targets[0] = address(govTarget);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(MockGovTarget.setValue, (42));
        description = "Set target value to 42";
    }

    function _propose() internal returns (uint256 proposalId) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        vm.prank(alice);
        proposalId = governor.propose(targets, values, calldatas, description);
    }

    function _advanceToActive() internal {
        vm.warp(block.timestamp + VOTING_DELAY + 1);
    }

    function _advancePastVoting() internal {
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
    }

    /// @dev Full flow: propose → active → both vote for → advance past voting.
    function _proposeAndVoteBothFor() internal returns (uint256 proposalId) {
        proposalId = _propose();
        _advanceToActive();
        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
        vm.prank(bob);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
        _advancePastVoting();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     END-TO-END: PROPOSE → EXECUTE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Full lifecycle: mint → delegate → propose → vote → queue → execute.
    function test_GovStack_FullLifecycle() public {
        // ---- 1. Initial token setup (done in setUp) ----
        assertEq(token.getVotes(alice), INITIAL_SUPPLY);
        assertEq(token.getVotes(bob), INITIAL_SUPPLY);

        // ---- 2. Propose ----
        uint256 proposalId = _propose();
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));

        // ---- 3. Voting period ----
        _advanceToActive();
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));

        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
        vm.prank(bob);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));

        _advancePastVoting();

        // ---- 4. State == Succeeded ----
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));

        // ---- 5. Queue ----
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        bytes32 descHash = keccak256(bytes(description));

        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        // ---- 6. Wait minDelay, then execute ----
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        governor.execute(targets, values, calldatas, descHash);

        // ---- 7. Verify target state changed ----
        assertEq(govTarget.value(), 42);
        assertTrue(govTarget.called());
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
    }

    /// @notice Both voters cast For — quorum and majority are met.
    function test_GovStack_BothVoteFor_QuorumMet() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
        vm.prank(bob);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));

        (uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(proposalId);
        assertEq(forVotes, 2 * INITIAL_SUPPLY);
        assertEq(against, 0);
        assertEq(abstain, 0);

        _advancePastVoting();
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    /// @notice Proposal is defeated when both voters vote Against.
    function test_GovStack_BothVoteAgainst_Defeated() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.Against));
        vm.prank(bob);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.Against));

        _advancePastVoting();
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    /// @notice Execute must wait for the timelock delay — premature call reverts.
    function test_GovStack_ExecuteRevertsBeforeTimelockDelay() public {
        uint256 proposalId = _proposeAndVoteBothFor();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        bytes32 descHash = keccak256(bytes(description));

        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        // Try to execute immediately (before minDelay).
        uint256 eta = governor.proposalEta(proposalId);
        vm.warp(eta - 1);

        vm.expectRevert(); // TimelockController reverts with insufficient delay
        governor.execute(targets, values, calldatas, descHash);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    CANCEL MID-FLIGHT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Proposer cancels an Active proposal.
    function test_GovStack_CancelActiveMidFlight() public {
        uint256 proposalId = _propose();
        _advanceToActive();
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();

        vm.expectEmit(false, false, false, true, address(governor));
        emit ProposalCanceled(proposalId);

        vm.prank(alice);
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Canceled));
        // Target should not have been called.
        assertFalse(govTarget.called());
    }

    /// @notice Proposer cancels a Queued proposal — the timelock op is also canceled.
    function test_GovStack_CancelQueuedProposalAlsoCancelsTimelockOp() public {
        uint256 proposalId = _proposeAndVoteBothFor();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        bytes32 descHash = keccak256(bytes(description));

        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        // Verify the timelock op exists.
        bytes32 salt = bytes32(proposalId);
        bytes32 timelockId = timelock.hashOperationBatch(targets, values, calldatas, bytes32(0), salt);
        assertTrue(timelock.isOperationPending(timelockId));

        // Alice (proposer) cancels.
        vm.prank(alice);
        governor.cancel(targets, values, calldatas, descHash);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Canceled));
        // Timelock op must also be canceled.
        assertFalse(timelock.isOperationPending(timelockId));
        assertFalse(govTarget.called());
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     GOVERNANCE PARAMETER UPDATES
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice quorumNumerator can be updated via a governance proposal.
    function test_GovStack_UpdateQuorumViaSelfProposal() public {
        // Deploy a governor with no timelock for quick self-governance.
        GovernorStandalone.Config memory cfg = GovernorStandalone.Config({
            name: "Self Gov",
            token: address(token),
            timelock: address(0),
            votingDelay: 0,
            votingPeriod: 1 days,
            proposalThreshold: 0,
            quorumNumerator: 4
        });
        GovernorStandalone selfGov = new GovernorStandalone(cfg);

        address[] memory targets = new address[](1);
        targets[0] = address(selfGov);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(IGovernor.updateQuorumNumerator, (10));
        string memory description = "Update quorum to 10%";

        vm.prank(alice);
        uint256 proposalId = selfGov.propose(targets, values, calldatas, description);

        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        selfGov.castVote(proposalId, uint8(IGovernor.VoteType.For));

        vm.warp(block.timestamp + 1 days + 1);
        selfGov.execute(targets, values, calldatas, keccak256(bytes(description)));

        assertEq(selfGov.quorumNumerator(), 10);
    }

    /// @notice quorumNumerator can be updated via a proposal executed THROUGH the timelock.
    /// @dev Regression: with a timelock configured, the governor's own admin setters are
    ///      invoked by the timelock (msg.sender == timelock), so `_checkGovernance` must
    ///      accept the configured executor — not only `address(this)`. Previously this
    ///      reverted with GovernorOnlyExecutor, bricking self-reconfiguration.
    function test_GovStack_UpdateQuorumViaTimelockProposal() public {
        assertEq(governor.quorumNumerator(), QUORUM_NUMERATOR);

        address[] memory targets = new address[](1);
        targets[0] = address(governor);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(IGovernor.updateQuorumNumerator, (10));
        string memory description = "Update quorum to 10% via timelock";
        bytes32 descHash = keccak256(bytes(description));

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        _advanceToActive();
        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
        vm.prank(bob);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
        _advancePastVoting();

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));

        governor.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        governor.execute(targets, values, calldatas, descHash);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
        assertEq(governor.quorumNumerator(), 10);
    }

    /// @notice The timelock cannot be used to invoke the governor's admin setters via a
    ///         queued operation that did NOT originate from a governor `execute()` call.
    /// @dev Defends the `_governanceCall` authorization: a timelock proposer scheduling
    ///      `updateQuorumNumerator` directly on the timelock must not be able to reconfigure
    ///      the governor when the timelock relays the call back.
    function test_GovStack_TimelockCannotForgeGovernanceCall() public {
        // admin holds no PROPOSER_ROLE for arbitrary ops by default, so grant the stranger
        // PROPOSER + EXECUTOR to simulate a timelock controlled outside the governor.
        vm.startPrank(admin);
        timelock.grantRole(TimelockControllerLib.PROPOSER_ROLE, stranger);
        timelock.grantRole(TimelockControllerLib.EXECUTOR_ROLE, stranger);
        vm.stopPrank();

        address[] memory targets = new address[](1);
        targets[0] = address(governor);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(IGovernor.updateQuorumNumerator, (99));
        bytes32 salt = bytes32(uint256(0xBEEF));

        vm.startPrank(stranger);
        timelock.scheduleBatch(targets, values, calldatas, bytes32(0), salt, TIMELOCK_DELAY);
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        // The timelock relays the call to the governor, but it was never authorized by a
        // governor execute(), so `_checkGovernance` must reject it.
        vm.expectRevert();
        timelock.executeBatch(targets, values, calldatas, bytes32(0), salt);
        vm.stopPrank();

        assertEq(governor.quorumNumerator(), QUORUM_NUMERATOR);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         MULTI-VOTER QUORUM MATH
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Verify that the quorum calculation uses both voters' supply.
    function test_GovStack_QuorumAccounting() public {
        uint256 proposalId = _propose();
        uint256 snapshot = governor.proposalSnapshot(proposalId);
        vm.warp(snapshot + 1);

        uint256 expectedQuorum = (2 * INITIAL_SUPPLY * QUORUM_NUMERATOR) / 100;
        assertEq(governor.quorum(snapshot), expectedQuorum);
    }

    /// @notice Abstain votes count toward quorum but not toward majority.
    function test_GovStack_AbstainCountsTowardQuorumNotMajority() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        // Alice votes For; bob abstains. Quorum is met (alice's INITIAL_SUPPLY > 4% of 2M).
        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
        vm.prank(bob);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.Abstain));

        _advancePastVoting();
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }
}
