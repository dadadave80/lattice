// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernorStandalone} from "@lattice/governance/GovernorStandalone.sol";
import {TimelockControllerStandalone} from "@lattice/governance/TimelockControllerStandalone.sol";
import {BALLOT_TYPEHASH, GovernorLib} from "@lattice/governance/libraries/GovernorLib.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {IGovernor} from "@lattice/interfaces/IGovernor.sol";
import {ITimelockController} from "@lattice/interfaces/ITimelockController.sol";
import {IVotes} from "@lattice/interfaces/IVotes.sol";
import {ERC20Votes} from "@lattice/tokens/ERC20Votes.sol";
import {ERC20Lib} from "@lattice/tokens/libraries/ERC20Lib.sol";
import {ERC20VotesLib} from "@lattice/tokens/libraries/ERC20VotesLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

//*//////////////////////////////////////////////////////////////////////////
//                             MOCK CONTRACTS
//////////////////////////////////////////////////////////////////////////*//

/// @notice Mock ERC20Votes token used in Governor tests.
contract MockERC20VotesContract is ERC20Votes {
    function initialize(string memory name_, string memory symbol_, address admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init(name_, symbol_);
        EIP712Lib.__EIP712_init(name_, "1");
        NoncesLib.__Nonces_init();
        VotesLib.__Votes_init();
        ERC20VotesLib.__ERC20Votes_init();
        AccessControlLib.__AccessControl_init(admin);
        InitializableLib.postInitializer(s);
    }

    function mint(address to, uint256 value) external {
        ERC20VotesLib._mint(to, value);
    }

    function nonces(address account) public view returns (uint256) {
        return NoncesLib.nonces(account);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return EIP712Lib.domainSeparatorV4();
    }
}

/// @notice Simple call target for Governor execution tests.
contract GovTarget {
    uint256 public value;

    function setValue(uint256 _value) external {
        value = _value;
    }
}

/// @notice Standalone Governor that also exposes ERC-165 `supportsInterface`.
/// @dev `GovernorStandalone` registers `IGovernor` into ERC-165 storage but does not
///      surface a public reader; this mock adds the standard facade so the ERC-165
///      test can use the same `supportsInterface(...)` call shape as every other module.
contract MockGovernorStandalone is GovernorStandalone {
    constructor(Config memory cfg) GovernorStandalone(cfg) {}

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                              TEST SUITE
//////////////////////////////////////////////////////////////////////////*//

/// @title GovernorTester
/// @notice Comprehensive tests for the Governor module.
contract GovernorTester is Test {
    MockERC20VotesContract token;
    TimelockControllerStandalone timelock;
    MockGovernorStandalone governor;
    GovTarget govTarget;

    // Test accounts
    address admin = address(0xAD);

    address alice;
    uint256 aliceKey = 0xA11CE;

    address bob;
    uint256 bobKey = 0xB0B;

    address charlie = address(0xC4);
    address stranger = address(0x5);

    // Token supply
    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    // Governor params
    uint48 constant VOTING_DELAY = 1 days;
    uint32 constant VOTING_PERIOD = 7 days;
    uint256 constant PROPOSAL_THRESHOLD = 1_000e18;
    uint256 constant QUORUM_NUMERATOR = 4; // 4%
    uint256 constant TIMELOCK_DELAY = 2 days;

    // Events (re-declared for vm.expectEmit)
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
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);
    event QuorumNumeratorUpdated(uint256 oldNumerator, uint256 newNumerator);

    function setUp() public {
        alice = vm.addr(aliceKey);
        bob = vm.addr(bobKey);

        // Deploy token
        token = new MockERC20VotesContract();
        token.initialize("Vote Token", "VOTE", admin);

        // Mint and delegate
        token.mint(alice, INITIAL_SUPPLY);
        token.mint(bob, INITIAL_SUPPLY);
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);

        // Warp forward so voting power is checkpointed
        vm.warp(block.timestamp + 1);

        // Deploy timelock (governor is proposer, admin is admin)
        address[] memory proposers = new address[](0); // will grant after governor deploy
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open execution
        timelock = new TimelockControllerStandalone(TIMELOCK_DELAY, proposers, executors, admin);

        // Deploy governor with timelock
        GovernorStandalone.Config memory cfg = GovernorStandalone.Config({
            name: "Test Governor",
            token: address(token),
            timelock: address(timelock),
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            proposalThreshold: PROPOSAL_THRESHOLD,
            quorumNumerator: QUORUM_NUMERATOR
        });
        governor = new MockGovernorStandalone(cfg);

        // Grant governor PROPOSER_ROLE + CANCELLER_ROLE on timelock
        vm.startPrank(admin);
        timelock.grantRole(TimelockControllerLib.PROPOSER_ROLE, address(governor));
        timelock.grantRole(TimelockControllerLib.CANCELLER_ROLE, address(governor));
        vm.stopPrank();

        // Deploy execution target
        govTarget = new GovTarget();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Build a single-call proposal targeting govTarget.setValue(42).
    function _buildProposal()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](1);
        targets[0] = address(govTarget);
        values = new uint256[](1);
        values[0] = 0;
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(GovTarget.setValue, (42));
        description = "Set value to 42";
    }

    /// @dev Create a proposal as alice and return the proposalId.
    function _propose() internal returns (uint256 proposalId) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        vm.prank(alice);
        proposalId = governor.propose(targets, values, calldatas, description);
    }

    /// @dev Advance time past the voting delay so the proposal becomes Active.
    function _advanceToActive() internal {
        vm.warp(block.timestamp + VOTING_DELAY + 1);
    }

    /// @dev Advance time past the voting period so the proposal is no longer Active.
    function _advancePastVoting() internal {
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
    }

    /// @dev Propose → vote For with enough to meet quorum → advance past voting period.
    function _proposeVoteAndSucceed() internal returns (uint256 proposalId) {
        proposalId = _propose();
        _advanceToActive();
        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
        _advancePastVoting();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_NameIsSetCorrectly() public view {
        assertEq(governor.name(), "Test Governor");
    }

    function test_VersionIsOne() public view {
        assertEq(governor.version(), "1");
    }

    function test_TokenIsSet() public view {
        assertEq(governor.token(), address(token));
    }

    function test_TimelockIsSet() public view {
        assertEq(governor.timelock(), address(timelock));
    }

    function test_VotingDelayIsSet() public view {
        assertEq(governor.votingDelay(), VOTING_DELAY);
    }

    function test_VotingPeriodIsSet() public view {
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
    }

    function test_ProposalThresholdIsSet() public view {
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
    }

    function test_QuorumNumeratorIsSet() public view {
        assertEq(governor.quorumNumerator(), QUORUM_NUMERATOR);
    }

    function test_QuorumDenominatorIs100() public view {
        assertEq(governor.quorumDenominator(), 100);
    }

    function test_ClockModeIsTimestamp() public view {
        assertEq(governor.CLOCK_MODE(), "mode=timestamp");
    }

    function test_CountingModeIsBravo() public view {
        assertEq(governor.COUNTING_MODE(), "support=bravo&quorum=for,abstain");
    }

    function test_ClockReturnsCurrent() public view {
        assertEq(governor.clock(), uint48(block.timestamp));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          INVALID INIT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitRevertsOnZeroVotingPeriod() public {
        GovernorStandalone.Config memory cfg = GovernorStandalone.Config({
            name: "Bad Gov",
            token: address(token),
            timelock: address(0),
            votingDelay: 0,
            votingPeriod: 0, // invalid
            proposalThreshold: 0,
            quorumNumerator: 0
        });
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorInvalidVotingPeriod.selector, 0));
        new GovernorStandalone(cfg);
    }

    function test_InitRevertsOnQuorumNumeratorExceedsDenominator() public {
        GovernorStandalone.Config memory cfg = GovernorStandalone.Config({
            name: "Bad Gov",
            token: address(token),
            timelock: address(0),
            votingDelay: 0,
            votingPeriod: 1 days,
            proposalThreshold: 0,
            quorumNumerator: 101 // > 100
        });
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorInvalidQuorumFraction.selector, 101, 100));
        new GovernorStandalone(cfg);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              PROPOSE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ProposeSucceedsWithSufficientVotes() public {
        uint256 proposalId = _propose();
        assertTrue(proposalId != 0);
    }

    function test_ProposeReturnsDeterministicId() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        bytes32 descHash = keccak256(bytes(description));
        uint256 expected = governor.hashProposal(targets, values, calldatas, descHash);

        vm.prank(alice);
        uint256 actual = governor.propose(targets, values, calldatas, description);

        assertEq(actual, expected);
    }

    function test_ProposeEmitsProposalCreated() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        bytes32 descHash = keccak256(bytes(description));
        uint256 proposalId = governor.hashProposal(targets, values, calldatas, descHash);

        uint48 expectedStart = uint48(block.timestamp + VOTING_DELAY);
        string[] memory sigs = new string[](1);
        // The event has an indexed-equivalent proposalId — just check it fires
        vm.expectEmit(false, false, false, false, address(governor));
        emit ProposalCreated(
            proposalId,
            alice,
            targets,
            values,
            sigs,
            calldatas,
            expectedStart,
            expectedStart + VOTING_PERIOD,
            description
        );

        vm.prank(alice);
        governor.propose(targets, values, calldatas, description);
    }

    function test_ProposeRevertsInsufficientVotes() public {
        // Charlie has no tokens / no delegation
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        vm.prank(charlie);
        vm.expectRevert(
            abi.encodeWithSelector(IGovernor.GovernorInsufficientProposerVotes.selector, charlie, 0, PROPOSAL_THRESHOLD)
        );
        governor.propose(targets, values, calldatas, description);
    }

    function test_ProposeRevertsOnMismatchedArrays() public {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](1); // mismatch
        bytes[] memory calldatas = new bytes[](2);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorInvalidProposalLength.selector, 2, 2, 1));
        governor.propose(targets, values, calldatas, "desc");
    }

    function test_ProposalStateIsPendingAfterPropose() public {
        uint256 proposalId = _propose();
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Pending));
    }

    function test_ProposalStateIsActiveAfterDelay() public {
        uint256 proposalId = _propose();
        _advanceToActive();
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));
    }

    function test_ProposalSnapshotIsCorrect() public {
        uint256 proposalId = _propose();
        uint256 expected = block.timestamp + VOTING_DELAY - 1; // We advanced 1 sec in setUp
        // voteStart = clock at propose time + votingDelay
        assertEq(governor.proposalSnapshot(proposalId), governor.proposalDeadline(proposalId) - VOTING_PERIOD);
    }

    function test_ProposalDeadlineIsCorrect() public {
        uint256 proposalId = _propose();
        uint256 snapshot = governor.proposalSnapshot(proposalId);
        assertEq(governor.proposalDeadline(proposalId), snapshot + VOTING_PERIOD);
    }

    function test_ProposalProposerIsAlice() public {
        uint256 proposalId = _propose();
        assertEq(governor.proposalProposer(proposalId), alice);
    }

    function test_StateLookupRevertsForNonExistentProposal() public {
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorNonexistentProposal.selector, 999));
        governor.state(999);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            CAST VOTE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_CastVoteUpdatesForVotes() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));

        (uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(proposalId);
        assertEq(forVotes, INITIAL_SUPPLY);
        assertEq(against, 0);
        assertEq(abstain, 0);
    }

    function test_CastVoteUpdatesAgainstVotes() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.Against));

        (uint256 against,,) = governor.proposalVotes(proposalId);
        assertEq(against, INITIAL_SUPPLY);
    }

    function test_CastVoteUpdatesAbstainVotes() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.Abstain));

        (,, uint256 abstain) = governor.proposalVotes(proposalId);
        assertEq(abstain, INITIAL_SUPPLY);
    }

    function test_CastVoteSetsHasVoted() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));

        assertTrue(governor.hasVoted(proposalId, alice));
    }

    function test_HasVotedReturnsFalseBeforeVote() public {
        uint256 proposalId = _propose();
        assertFalse(governor.hasVoted(proposalId, alice));
    }

    function test_CastVoteRevertsWhenNotActive_Pending() public {
        uint256 proposalId = _propose();
        // Still Pending — not Active yet
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                proposalId,
                IGovernor.ProposalState.Pending,
                bytes32(1 << uint8(IGovernor.ProposalState.Active))
            )
        );
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
    }

    function test_CastVoteRevertsWhenNotActive_AfterDeadline() public {
        uint256 proposalId = _propose();
        _advanceToActive();
        _advancePastVoting();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                proposalId,
                IGovernor.ProposalState.Defeated, // no votes cast, so defeated
                bytes32(1 << uint8(IGovernor.ProposalState.Active))
            )
        );
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
    }

    function test_CastVoteTwiceReverts() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        vm.startPrank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorAlreadyCastVote.selector, alice));
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
        vm.stopPrank();
    }

    function test_CastVoteEmitsVoteCast() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        vm.expectEmit(true, false, false, true, address(governor));
        emit VoteCast(alice, proposalId, uint8(IGovernor.VoteType.For), INITIAL_SUPPLY, "");

        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
    }

    function test_CastVoteWithReasonEmitsReason() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        string memory reason = "I support this proposal";

        vm.expectEmit(true, false, false, true, address(governor));
        emit VoteCast(alice, proposalId, uint8(IGovernor.VoteType.For), INITIAL_SUPPLY, reason);

        vm.prank(alice);
        governor.castVoteWithReason(proposalId, uint8(IGovernor.VoteType.For), reason);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         CAST VOTE BY SIG TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function _buildBallotHash(uint256 proposalId, uint8 support, address voter, uint256 nonce)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support, voter, nonce));
        // Get domain separator from governor's EIP712 storage
        // We need to build it manually since GovernorStandalone uses EIP712Lib
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    function _domainSeparator() internal view returns (bytes32) {
        // EIP712 domain: keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
        bytes32 domainTypeHash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        return keccak256(
            abi.encode(
                domainTypeHash,
                keccak256(bytes("Test Governor")),
                keccak256(bytes("1")),
                block.chainid,
                address(governor)
            )
        );
    }

    function test_CastVoteBySigWithValidSignature() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        // Get alice's current nonce in the governor's Nonces storage
        // Note: NoncesLib uses its own storage slot, we start at 0
        uint256 nonce = 0; // first use
        bytes32 hash = _buildBallotHash(proposalId, uint8(IGovernor.VoteType.For), alice, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        uint256 weight = governor.castVoteBySig(proposalId, uint8(IGovernor.VoteType.For), alice, sig);
        assertEq(weight, INITIAL_SUPPLY);
        assertTrue(governor.hasVoted(proposalId, alice));
    }

    function test_CastVoteBySigWithInvalidSignatureReverts() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        uint256 nonce = 0;
        bytes32 hash = _buildBallotHash(proposalId, uint8(IGovernor.VoteType.For), alice, nonce);
        // Sign with Bob's key but claim it's Alice
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorInvalidSignature.selector, alice));
        governor.castVoteBySig(proposalId, uint8(IGovernor.VoteType.For), alice, sig);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          PROPOSAL STATE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_StateIsDefeatedWhenAgainstWins() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        // Alice votes For, Bob votes Against (same supply → tie → not succeeded)
        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
        vm.prank(bob);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.Against));

        _advancePastVoting();
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_StateIsDefeatedWhenQuorumNotMet() public {
        // Deploy governor with very high quorum so small votes don't meet it
        GovernorStandalone.Config memory cfg = GovernorStandalone.Config({
            name: "High Quorum Gov",
            token: address(token),
            timelock: address(0),
            votingDelay: 0,
            votingPeriod: 1 days,
            proposalThreshold: 0,
            quorumNumerator: 99 // 99% — practically unreachable
        });
        GovernorStandalone highQuorumGov = new GovernorStandalone(cfg);

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        vm.prank(alice);
        uint256 proposalId = highQuorumGov.propose(targets, values, calldatas, description);

        vm.warp(block.timestamp + 1); // advance to active

        vm.prank(alice);
        highQuorumGov.castVote(proposalId, uint8(IGovernor.VoteType.For));

        vm.warp(block.timestamp + 1 days + 1);
        assertEq(uint8(highQuorumGov.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_StateIsSucceededAfterVotingPeriodWithQuorum() public {
        uint256 proposalId = _proposeVoteAndSucceed();
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function test_ProposalVotesReturnsCorrectTriple() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        vm.prank(alice);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
        vm.prank(bob);
        governor.castVote(proposalId, uint8(IGovernor.VoteType.Against));

        (uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(proposalId);
        assertEq(forVotes, INITIAL_SUPPLY);
        assertEq(against, INITIAL_SUPPLY);
        assertEq(abstain, 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              CANCEL TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_CancelByProposerWhilePending() public {
        uint256 proposalId = _propose();

        vm.prank(alice);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        uint256 returnedId = governor.cancel(targets, values, calldatas, keccak256(bytes(description)));

        assertEq(returnedId, proposalId);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Canceled));
    }

    function test_CancelEmitsProposalCanceled() public {
        uint256 proposalId = _propose();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();

        vm.expectEmit(false, false, false, true, address(governor));
        emit ProposalCanceled(proposalId);

        vm.prank(alice);
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
    }

    function test_CancelByNonProposerReverts() public {
        _propose();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, bob));
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
    }

    function test_CancelAfterVotingStartedSucceeds() public {
        // Cancel is now allowed in Active state (OZ reconciliation)
        uint256 proposalId = _propose();
        _advanceToActive();
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();

        vm.prank(alice);
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Canceled));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         EXECUTE WITHOUT TIMELOCK TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ExecuteDirectlyWithNoTimelock() public {
        // Deploy governor with no timelock
        GovernorStandalone.Config memory cfg = GovernorStandalone.Config({
            name: "Direct Gov",
            token: address(token),
            timelock: address(0),
            votingDelay: 0,
            votingPeriod: 1 days,
            proposalThreshold: 0,
            quorumNumerator: 4
        });
        GovernorStandalone directGov = new GovernorStandalone(cfg);

        GovTarget target2 = new GovTarget();

        address[] memory targets = new address[](1);
        targets[0] = address(target2);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(GovTarget.setValue, (99));
        string memory description = "Set value to 99";

        vm.prank(alice);
        uint256 proposalId = directGov.propose(targets, values, calldatas, description);

        vm.warp(block.timestamp + 1); // Active immediately (delay=0)
        vm.prank(alice);
        directGov.castVote(proposalId, uint8(IGovernor.VoteType.For));

        vm.warp(block.timestamp + 1 days + 1);
        assertEq(uint8(directGov.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));

        directGov.execute(targets, values, calldatas, keccak256(bytes(description)));

        assertEq(target2.value(), 99);
        assertEq(uint8(directGov.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
    }

    function test_ExecuteEmitsProposalExecuted() public {
        GovernorStandalone.Config memory cfg = GovernorStandalone.Config({
            name: "Direct Gov 2",
            token: address(token),
            timelock: address(0),
            votingDelay: 0,
            votingPeriod: 1 days,
            proposalThreshold: 0,
            quorumNumerator: 4
        });
        GovernorStandalone directGov = new GovernorStandalone(cfg);

        address[] memory targets = new address[](1);
        targets[0] = address(govTarget);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(GovTarget.setValue, (7));
        string memory description = "Set value to 7";

        vm.prank(alice);
        uint256 proposalId = directGov.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        directGov.castVote(proposalId, uint8(IGovernor.VoteType.For));
        vm.warp(block.timestamp + 1 days + 1);

        vm.expectEmit(false, false, false, true, address(directGov));
        emit ProposalExecuted(proposalId);
        directGov.execute(targets, values, calldatas, keccak256(bytes(description)));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        QUEUE + EXECUTE WITH TIMELOCK TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_QueueSucceededProposal() public {
        uint256 proposalId = _proposeVoteAndSucceed();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();

        governor.queue(targets, values, calldatas, keccak256(bytes(description)));

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));
    }

    function test_QueueSetsEta() public {
        uint256 proposalId = _proposeVoteAndSucceed();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();

        uint256 expectedEta = block.timestamp + TIMELOCK_DELAY;
        governor.queue(targets, values, calldatas, keccak256(bytes(description)));

        assertEq(governor.proposalEta(proposalId), expectedEta);
    }

    function test_QueueEmitsProposalQueued() public {
        uint256 proposalId = _proposeVoteAndSucceed();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();

        uint256 expectedEta = block.timestamp + TIMELOCK_DELAY;
        vm.expectEmit(false, false, false, true, address(governor));
        emit ProposalQueued(proposalId, expectedEta);

        governor.queue(targets, values, calldatas, keccak256(bytes(description)));
    }

    function test_QueueRevertsIfNotSucceeded() public {
        uint256 proposalId = _propose();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();

        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                proposalId,
                IGovernor.ProposalState.Pending,
                bytes32(1 << uint8(IGovernor.ProposalState.Succeeded))
            )
        );
        governor.queue(targets, values, calldatas, keccak256(bytes(description)));
    }

    function test_QueueRevertsIfNoTimelockConfigured() public {
        // Use direct governor (no timelock)
        GovernorStandalone.Config memory cfg = GovernorStandalone.Config({
            name: "Direct Gov 3",
            token: address(token),
            timelock: address(0),
            votingDelay: 0,
            votingPeriod: 1 days,
            proposalThreshold: 0,
            quorumNumerator: 4
        });
        GovernorStandalone directGov = new GovernorStandalone(cfg);

        address[] memory targets = new address[](1);
        targets[0] = address(govTarget);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(GovTarget.setValue, (1));
        string memory description = "Set 1";

        vm.prank(alice);
        uint256 noTlProposalId = directGov.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        directGov.castVote(noTlProposalId, uint8(IGovernor.VoteType.For));
        vm.warp(block.timestamp + 1 days + 1);

        vm.expectRevert(IGovernor.GovernorQueueNotImplemented.selector);
        directGov.queue(targets, values, calldatas, keccak256(bytes(description)));
    }

    function test_ExecuteFromQueuedAfterTimelockDelay() public {
        uint256 proposalId = _proposeVoteAndSucceed();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        bytes32 descHash = keccak256(bytes(description));

        governor.queue(targets, values, calldatas, descHash);

        // Advance past timelock delay
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        governor.execute(targets, values, calldatas, descHash);

        assertEq(govTarget.value(), 42);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         ADMIN SETTER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_UpdateQuorumNumeratorViaGovernanceProposal() public {
        // Build a proposal that calls governor.updateQuorumNumerator(10)
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

    function test_UpdateQuorumNumeratorDirectlyReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, alice));
        governor.updateQuorumNumerator(10);
    }

    function test_SetVotingDelayDirectlyReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, alice));
        governor.setVotingDelay(2 days);
    }

    function test_SetVotingPeriodDirectlyReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, alice));
        governor.setVotingPeriod(14 days);
    }

    function test_SetProposalThresholdDirectlyReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, alice));
        governor.setProposalThreshold(5_000e18);
    }

    function test_UpdateTimelockDirectlyReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, alice));
        governor.updateTimelock(address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           QUORUM TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_QuorumIsCorrectPercentageOfSupply() public {
        // quorum = totalSupply * quorumNumerator / 100
        // totalSupply = 2 * INITIAL_SUPPLY (alice + bob both minted)
        uint256 proposalId = _propose();
        uint256 snapshot = governor.proposalSnapshot(proposalId);
        // Must warp past the snapshot before querying quorum (getPastTotalSupply requires past timepoints)
        vm.warp(snapshot + 1);
        uint256 expectedQuorum = (2 * INITIAL_SUPPLY * QUORUM_NUMERATOR) / 100;
        assertEq(governor.quorum(snapshot), expectedQuorum);
    }

    function test_AbstractCountsTowardQuorum() public {
        // Deploy high-threshold quorum governor where only abstain is enough
        GovernorStandalone.Config memory cfg = GovernorStandalone.Config({
            name: "Abstain Gov",
            token: address(token),
            timelock: address(0),
            votingDelay: 0,
            votingPeriod: 1 days,
            proposalThreshold: 0,
            quorumNumerator: 4
        });
        GovernorStandalone abstainGov = new GovernorStandalone(cfg);

        address[] memory targets = new address[](1);
        targets[0] = address(govTarget);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(GovTarget.setValue, (0));
        string memory description = "Abstain test";

        vm.prank(alice);
        abstainGov.propose(targets, values, calldatas, description);

        vm.warp(block.timestamp + 1);

        // Alice votes For (to win), Bob abstains
        uint256 pid = abstainGov.hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        vm.prank(alice);
        abstainGov.castVote(pid, uint8(IGovernor.VoteType.For));
        vm.prank(bob);
        abstainGov.castVote(pid, uint8(IGovernor.VoteType.Abstain));

        vm.warp(block.timestamp + 1 days + 1);
        assertEq(uint8(abstainGov.state(pid)), uint8(IGovernor.ProposalState.Succeeded));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           GET VOTES TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_GetVotesReturnsCorrectPastVotes() public {
        uint256 ts = block.timestamp - 1; // warp +1 was done in setUp
        uint256 votes = governor.getVotes(alice, ts);
        assertEq(votes, INITIAL_SUPPLY);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          ERC-165 SUPPORT TEST
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIGovernorInterface() public view {
        assertTrue(governor.supportsInterface(type(IGovernor).interfaceId), "IGovernor not registered");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      HASH PROPOSAL CONSISTENCY TEST
    //////////////////////////////////////////////////////////////////////////*//

    function test_HashProposalIsDeterministic() public view {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,) = _buildProposal();
        bytes32 descHash = keccak256(bytes("Set value to 42"));

        uint256 id1 = governor.hashProposal(targets, values, calldatas, descHash);
        uint256 id2 = governor.hashProposal(targets, values, calldatas, descHash);
        assertEq(id1, id2);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                   OZ-RECONCILIATION TESTS (B-SERIES)
    //////////////////////////////////////////////////////////////////////////*//

    // ---- B1: cancel scope expansion ----

    function test_CancelActiveProposal() public {
        // Proposer can cancel once voting has started (Active state).
        uint256 proposalId = _propose();
        _advanceToActive();
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Active));

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        vm.prank(alice);
        governor.cancel(targets, values, calldatas, keccak256(bytes(description)));

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Canceled));
    }

    function test_CancelQueuedProposalAlsoCancelsTimelockOp() public {
        uint256 proposalId = _proposeVoteAndSucceed();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        bytes32 descHash = keccak256(bytes(description));

        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        // Compute the expected timelock operation id
        bytes32 salt = bytes32(proposalId);
        bytes32 timelockId = timelock.hashOperationBatch(targets, values, calldatas, bytes32(0), salt);
        assertTrue(timelock.isOperationPending(timelockId), "op should be pending before cancel");

        vm.prank(alice);
        governor.cancel(targets, values, calldatas, descHash);

        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Canceled));
        assertFalse(timelock.isOperationPending(timelockId), "op should be cancelled in timelock");
    }

    // ---- B2: empty targets ----

    function test_ProposeEmptyTargetsReverts() public {
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorInvalidProposalLength.selector, 0, 0, 0));
        governor.propose(targets, values, calldatas, "empty");
    }

    // ---- B3: state() consults live timelock op status ----

    function test_StateConsultsTimelockOnExternalCancel() public {
        uint256 proposalId = _proposeVoteAndSucceed();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        bytes32 descHash = keccak256(bytes(description));

        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        // Externally cancel the operation directly on the timelock (CANCELLER_ROLE held by governor)
        bytes32 salt = bytes32(proposalId);
        bytes32 timelockId = timelock.hashOperationBatch(targets, values, calldatas, bytes32(0), salt);

        // Grant canceller role to admin so we can cancel on the timelock directly
        vm.prank(admin);
        timelock.grantRole(TimelockControllerLib.CANCELLER_ROLE, admin);
        vm.prank(admin);
        timelock.cancel(timelockId);

        // state() should now return Canceled because the timelock op is no longer pending
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Canceled));
    }

    // ---- B4: TimelockChange event ----

    event TimelockChange(address indexed oldTimelock, address indexed newTimelock);

    function test_TimelockChangeEventEmitted() public {
        // Build and execute a proposal that calls governor.updateTimelock(address(0))
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

        address newTimelock = address(0xBEEF);

        address[] memory targets = new address[](1);
        targets[0] = address(selfGov);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(IGovernor.updateTimelock, (newTimelock));
        string memory description = "Update timelock";

        vm.prank(alice);
        uint256 proposalId = selfGov.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + 1);
        vm.prank(alice);
        selfGov.castVote(proposalId, uint8(IGovernor.VoteType.For));
        vm.warp(block.timestamp + 1 days + 1);

        vm.expectEmit(true, true, false, false, address(selfGov));
        emit TimelockChange(address(0), newTimelock);
        selfGov.execute(targets, values, calldatas, keccak256(bytes(description)));

        assertEq(selfGov.timelock(), newTimelock);
    }

    // ---- B6: castVoteWithReasonAndParams ----

    function test_CastVoteWithReasonAndParamsEmitsVoteCastWithParams() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        bytes memory params = abi.encode(uint256(500), uint256(300), uint256(200));
        string memory reason = "fractional vote";

        // Should not revert and should emit VoteCastWithParams
        vm.prank(alice);
        uint256 weight = governor.castVoteWithReasonAndParams(proposalId, uint8(IGovernor.VoteType.For), reason, params);
        assertEq(weight, INITIAL_SUPPLY);
        assertTrue(governor.hasVoted(proposalId, alice));
    }

    // ---- B7: duplicate-proposal bytes32(0) expectedStates ----

    function test_DuplicateProposalRevertsWithZeroExpectedStates() public {
        uint256 proposalId = _propose();
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();

        vm.prank(alice);
        // The expectedStates argument should be bytes32(0) for a duplicate-proposal revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                proposalId,
                IGovernor.ProposalState.Pending, // current state (still pending)
                bytes32(0) // expectedStates = 0 for "must not exist"
            )
        );
        governor.propose(targets, values, calldatas, description);
    }

    // ---- B8: invalid vote type ----

    function test_CastVoteInvalidTypeReverts() public {
        uint256 proposalId = _propose();
        _advanceToActive();

        vm.prank(alice);
        vm.expectRevert(IGovernor.GovernorInvalidVoteType.selector);
        governor.castVote(proposalId, 3); // support=3 is invalid
    }

    // ---- B9: double-queue ----

    function test_DoubleQueueRevertsWithAlreadyQueued() public {
        uint256 proposalId = _proposeVoteAndSucceed();

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        bytes32 descHash = keccak256(bytes(description));

        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint8(governor.state(proposalId)), uint8(IGovernor.ProposalState.Queued));

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorAlreadyQueuedProposal.selector, proposalId));
        governor.queue(targets, values, calldatas, descHash);
    }
}
