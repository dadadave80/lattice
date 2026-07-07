// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernorStandalone} from "@lattice/governance/GovernorStandalone.sol";
import {TimelockControllerStandalone} from "@lattice/governance/TimelockControllerStandalone.sol";
import {Votes} from "@lattice/governance/Votes.sol";
import {GovernorLib} from "@lattice/governance/libraries/GovernorLib.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Votes} from "@lattice/tokens/ERC20/ERC20Votes.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC20VotesLib} from "@lattice/tokens/ERC20/libraries/ERC20VotesLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                             MOCK CONTRACTS
//////////////////////////////////////////////////////////////////////////*//

/// @notice Mock ERC20Votes token used in governance gas tests. Flattens the composable {ERC20}, {Votes}, and
///         {ERC20Votes} facets into one mock; the checkpoint/balance-aware overrides win the clashes.
contract GovGasERC20Votes is ERC20, Votes, ERC20Votes {
    function transfer(address to, uint256 value) public override(ERC20, ERC20Votes) returns (bool) {
        return ERC20Votes.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override(ERC20, ERC20Votes) returns (bool) {
        return ERC20Votes.transferFrom(from, to, value);
    }

    function delegate(address delegatee) public override(Votes, ERC20Votes) {
        ERC20Votes.delegate(delegatee);
    }

    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        override(Votes, ERC20Votes)
    {
        ERC20Votes.delegateBySig(delegatee, nonce, expiry, v, r, s);
    }

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
}

/// @notice Mock AccessControl for checkRole gas tests.
contract GovGasAccessControl is AccessControl {
    bytes32 public constant VOTER_ROLE = keccak256("VOTER_ROLE");

    function initialize(address admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin);
        InitializableLib.postInitializer(s);
    }

    /// @notice Exposed checkRole for gas measurement.
    function checkRoleExposed(bytes32 role) external view {
        AccessControlLib.checkRole(role);
    }
}

/// @notice Simple call target for Governor execution tests.
contract GovGasTarget {
    uint256 public value;

    function setValue(uint256 _value) external {
        value = _value;
    }
}

/// @title GovernanceGasTest
/// @notice Gas snapshot tests for hot paths in the governance modules.
contract GovernanceGasTest is Test {
    GovGasERC20Votes token;
    TimelockControllerStandalone timelock;
    GovernorStandalone governor;
    GovGasTarget govTarget;
    GovGasAccessControl accessControl;

    address admin = address(0xAD);
    address alice = address(0xA1);
    address bob = address(0xB0B);
    address proposer = address(0xF001);
    address executor = address(0xF002);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;
    uint48 constant VOTING_DELAY = 1 days;
    uint32 constant VOTING_PERIOD = 7 days;
    uint256 constant PROPOSAL_THRESHOLD = 1_000e18;
    uint256 constant QUORUM_NUMERATOR = 4;
    uint256 constant TIMELOCK_DELAY = 2 days;
    uint256 constant MIN_DELAY = 2 days;

    // Generous upper bounds (~3× expected).
    uint256 constant GAS_BOUND_CAST_VOTE = 200_000;
    uint256 constant GAS_BOUND_CHECK_ROLE = 30_000;
    uint256 constant GAS_BOUND_SCHEDULE = 200_000;

    function setUp() public {
        // Deploy governance token.
        token = new GovGasERC20Votes();
        token.initialize("Gov Token", "GOV", admin);

        token.mint(alice, INITIAL_SUPPLY);
        token.mint(bob, INITIAL_SUPPLY);
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);

        // Checkpoint voting power.
        vm.warp(block.timestamp + 1);

        // Deploy timelock.
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open execution
        timelock = new TimelockControllerStandalone(TIMELOCK_DELAY, proposers, executors, admin);

        // Deploy governor.
        GovernorStandalone.Config memory cfg = GovernorStandalone.Config({
            name: "Gas Governor",
            token: address(token),
            timelock: address(timelock),
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            proposalThreshold: PROPOSAL_THRESHOLD,
            quorumNumerator: QUORUM_NUMERATOR
        });
        governor = new GovernorStandalone(cfg);

        // Grant proposer/canceller roles to governor on timelock.
        vm.startPrank(admin);
        timelock.grantRole(TimelockControllerLib.PROPOSER_ROLE, address(governor));
        timelock.grantRole(TimelockControllerLib.CANCELLER_ROLE, address(governor));
        vm.stopPrank();

        govTarget = new GovGasTarget();

        // Deploy standalone AccessControl for checkRole tests.
        accessControl = new GovGasAccessControl();
        accessControl.initialize(admin);

        // Grant VOTER_ROLE to alice so the cheap path can be measured.
        bytes32 _voterRole = accessControl.VOTER_ROLE();
        vm.prank(admin);
        accessControl.grantRole(_voterRole, alice);
    }

    /// @notice Helper: build a single-call proposal and create it as alice.
    function _propose() internal returns (uint256 proposalId) {
        address[] memory targets = new address[](1);
        targets[0] = address(govTarget);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(GovGasTarget.setValue, (42));
        string memory description = "Set value to 42";

        vm.prank(alice);
        proposalId = governor.propose(targets, values, calldatas, description);
    }

    /// @notice Gas cost of castVote (the hot path for a voter with sufficient weight).
    function test_Gas_GovernorCastVote() public {
        uint256 proposalId = _propose();
        // Advance past voting delay so the proposal becomes Active.
        vm.warp(block.timestamp + VOTING_DELAY + 1);

        vm.prank(alice);
        vm.startSnapshotGas("Governor.castVote");
        governor.castVote(proposalId, uint8(IGovernor.VoteType.For));
        uint256 gasUsed = vm.stopSnapshotGas();

        assertLt(gasUsed, GAS_BOUND_CAST_VOTE, "Governor.castVote gas regression");
    }

    /// @notice Gas cost of checkRole for a member (the cheap/happy path).
    function test_Gas_AccessControlCheckRole() public {
        // alice has VOTER_ROLE — checkRole should pass cheaply.
        bytes32 voterRole = accessControl.VOTER_ROLE();
        vm.prank(alice);
        vm.startSnapshotGas("AccessControl.checkRole.member");
        accessControl.checkRoleExposed(voterRole);
        uint256 gasUsed = vm.stopSnapshotGas();

        assertLt(gasUsed, GAS_BOUND_CHECK_ROLE, "AccessControl.checkRole.member gas regression");
    }

    /// @notice Gas cost of a single TimelockController schedule call.
    function test_Gas_TimelockSchedule() public {
        // Grant proposer role to the test contract so it can schedule.
        vm.prank(admin);
        timelock.grantRole(TimelockControllerLib.PROPOSER_ROLE, address(this));

        bytes memory data = abi.encodeCall(GovGasTarget.setValue, (99));

        vm.startSnapshotGas("TimelockController.schedule");
        timelock.schedule(address(govTarget), 0, data, bytes32(0), bytes32(0), MIN_DELAY);
        uint256 gasUsed = vm.stopSnapshotGas();

        assertLt(gasUsed, GAS_BOUND_SCHEDULE, "TimelockController.schedule gas regression");
    }
}
