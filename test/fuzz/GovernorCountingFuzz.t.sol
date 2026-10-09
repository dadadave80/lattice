// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GovernedVaultTestBase} from "@lattice-test/base/GovernedVaultTestBase.sol";
import {GovernedVault} from "@lattice/defi/GovernedVault.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";

/// @notice Minimal mintable underlying for the counting fuzz (no fees, no hooks).
contract CountingFuzzAsset {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }
}

/// @title GovernorCountingFuzz
/// @notice Differential test of the Governor's bravo vote counting on the PRODUCTION self-governed vault diamond
///         ({DeployGovernedVault}): fuzzed delegations, deposits, a share transfer, a redemption and ballots are
///         replayed into a mapping-based reference tally that never reads the Votes checkpoints. Each voter's
///         weight is the sum of the share balances delegated to it, moved on every mint, transfer and burn; quorum
///         is `supply * numerator / 100` over the tallied supply; the outcome is Succeeded iff `for > against` and
///         `for + abstain >= quorum`, else Defeated.
contract GovernorCountingFuzz is GovernedVaultTestBase {
    uint256 internal constant VOTERS = 6;
    uint48 internal constant VOTING_DELAY = 1;
    uint32 internal constant VOTING_PERIOD = 50;
    uint256 internal constant QUORUM_NUMERATOR = 4;

    GovernedVault internal vault;
    Governor internal gov;
    IVotes internal votes;
    IVaultCore internal vc;
    CountingFuzzAsset internal asset;

    mapping(address holder => address) internal refDelegate;
    mapping(address voter => uint256) internal refWeight;
    mapping(uint8 support => uint256) internal refTally;
    uint256 internal refSupply;

    /// @param transferSeed Picks the sender (`% VOTERS`) and recipient (`/ VOTERS % VOTERS`) of the share transfer.
    /// @param transferAmount Shares moved, bounded to the sender's balance.
    /// @param redeemSeed Picks the redeeming voter (`% VOTERS`).
    /// @param redeemAmount Shares redeemed, bounded to the redeemer's balance.
    struct Moves {
        uint256 transferSeed;
        uint256 transferAmount;
        uint256 redeemSeed;
        uint256 redeemAmount;
    }

    function setUp() public {
        vm.warp(1_000_000);
        asset = new CountingFuzzAsset();
        GovernedVaultParams memory p;
        p.name = "Counting Vault Share";
        p.symbol = "cVLT";
        p.minDelay = 100;
        p.votingDelay = VOTING_DELAY;
        p.votingPeriod = VOTING_PERIOD;
        p.quorumNumerator = QUORUM_NUMERATOR;
        address d = _deployGovernedVault(address(asset), p);
        vault = GovernedVault(d);
        gov = Governor(d);
        votes = IVotes(d);
        vc = IVaultCore(d);
    }

    /// @notice Per-voter weights, the three tallies, quorum and the final state all match the reference.
    /// @param deposits Asset amounts each voter deposits (bounded to [1, 1e30]).
    /// @param delegateTo Each voter's delegatee: `% 7` picks voter 0..5, or 6 for "never delegates".
    /// @param delegateFirst Bit `i` set: voter `i` delegates BEFORE depositing, so its mint moves the votes.
    /// @param moves A share transfer and a redemption made after delegation, before the snapshot.
    /// @param ballots Each voter's ballot: `% 5` is Against / For / Abstain, 3 abstains from voting, 4 casts an
    ///        invalid support value (which must revert and count nothing).
    function testFuzz_TallyMatchesMappingReference(
        uint256[VOTERS] memory deposits,
        uint8[VOTERS] memory delegateTo,
        uint8 delegateFirst,
        Moves memory moves,
        uint8[VOTERS] memory ballots
    ) public {
        _fundAndDelegate(deposits, delegateTo, delegateFirst);
        _transferAndRedeem(moves);
        vm.warp(block.timestamp + 1); // move the checkpoints behind the proposal snapshot
        uint256 proposalId = _proposeAndActivate();

        for (uint256 i; i < VOTERS; ++i) {
            _cast(proposalId, _voter(i), ballots[i] % 5);
        }

        (uint256 against, uint256 for_, uint256 abstain) = gov.proposalVotes(proposalId);
        assertEq(against, refTally[uint8(IGovernor.VoteType.Against)], "against tally");
        assertEq(for_, refTally[uint8(IGovernor.VoteType.For)], "for tally");
        assertEq(abstain, refTally[uint8(IGovernor.VoteType.Abstain)], "abstain tally");

        uint256 snapshot = gov.proposalSnapshot(proposalId);
        vm.warp(gov.proposalDeadline(proposalId) + 1);

        uint256 refQuorum = refSupply * QUORUM_NUMERATOR / 100;
        assertEq(gov.quorum(snapshot), refQuorum, "quorum");
        IGovernor.ProposalState expected = (for_ > against && for_ + abstain >= refQuorum)
            ? IGovernor.ProposalState.Succeeded
            : IGovernor.ProposalState.Defeated;
        assertEq(uint8(gov.state(proposalId)), uint8(expected), "final state");
    }

    /// @notice Quorum is inclusive: `for + abstain == quorum` succeeds, one unit short is defeated.
    /// @dev Voter 1 (a non-voting bystander) holds 96e18 shares; voter 0 votes For with 3e18 and voter 2 Abstains
    ///      with 1e18, so `for + abstain = 4e18`. With 96e18 the supply is 100e18 and quorum is exactly 4e18; with
    ///      96e18 + 25 the quorum rounds to 4e18 + 1.
    function test_QuorumBoundary_ForPlusAbstainEqualsQuorum_Succeeds() public {
        assertEq(_quorumCase(96e18, 4e18), uint8(IGovernor.ProposalState.Succeeded), "quorum met exactly");
    }

    function test_QuorumBoundary_OneUnitShort_Defeated() public {
        assertEq(_quorumCase(96e18 + 25, 4e18 + 1), uint8(IGovernor.ProposalState.Defeated), "quorum missed by 1");
    }

    function _quorumCase(uint256 bystander, uint256 expectedQuorum) internal returns (uint8) {
        _depositAndSelfDelegate(_voter(0), 3e18);
        _depositAndSelfDelegate(_voter(1), bystander);
        _depositAndSelfDelegate(_voter(2), 1e18);
        vm.warp(block.timestamp + 1);
        uint256 proposalId = _proposeAndActivate();

        vm.prank(_voter(0));
        assertEq(gov.castVote(proposalId, uint8(IGovernor.VoteType.For)), 3e18, "for weight");
        vm.prank(_voter(2));
        assertEq(gov.castVote(proposalId, uint8(IGovernor.VoteType.Abstain)), 1e18, "abstain weight");

        assertEq(gov.quorum(gov.proposalSnapshot(proposalId)), expectedQuorum, "quorum");
        vm.warp(gov.proposalDeadline(proposalId) + 1);
        return uint8(gov.state(proposalId));
    }

    function _depositAndSelfDelegate(address voter, uint256 amount) internal {
        asset.mint(voter, amount);
        vm.startPrank(voter);
        asset.approve(address(vault), amount);
        assertEq(vault.deposit(amount, voter), amount, "1:1 shares");
        votes.delegate(voter);
        vm.stopPrank();
    }

    /// @dev Delegates the `delegateFirst` voters, deposits for every voter, then delegates the rest. A mint or a
    ///      delegation credits the holder's delegatee in the reference.
    function _fundAndDelegate(uint256[VOTERS] memory deposits, uint8[VOTERS] memory delegateTo, uint8 delegateFirst)
        internal
    {
        for (uint256 i; i < VOTERS; ++i) {
            if (delegateFirst & (1 << i) != 0) _delegate(_voter(i), delegateTo[i]);
        }
        for (uint256 i; i < VOTERS; ++i) {
            address voter = _voter(i);
            uint256 amount = bound(deposits[i], 1, 1e30);
            asset.mint(voter, amount);
            vm.startPrank(voter);
            asset.approve(address(vault), amount);
            uint256 shares = vault.deposit(amount, voter);
            vm.stopPrank();
            refSupply += shares;
            _credit(voter, shares);
        }
        for (uint256 i; i < VOTERS; ++i) {
            if (delegateFirst & (1 << i) == 0) _delegate(_voter(i), delegateTo[i]);
        }
    }

    /// @dev Moves shares between two voters, then burns some of one voter's shares, mirroring both moves.
    function _transferAndRedeem(Moves memory m) internal {
        address from = _voter(m.transferSeed % VOTERS);
        address to = _voter(m.transferSeed / VOTERS % VOTERS);
        uint256 amount = bound(m.transferAmount, 0, vc.balanceOf(from));
        vm.prank(from);
        vc.transfer(to, amount);
        _debit(from, amount);
        _credit(to, amount);

        address redeemer = _voter(m.redeemSeed % VOTERS);
        uint256 shares = bound(m.redeemAmount, 0, vc.balanceOf(redeemer));
        if (shares == 0) return;
        vm.prank(redeemer);
        vault.redeem(shares, redeemer, redeemer);
        refSupply -= shares;
        _debit(redeemer, shares);
    }

    function _delegate(address voter, uint8 delegateTo) internal {
        uint256 target = delegateTo % (VOTERS + 1);
        if (target == VOTERS) return;
        vm.prank(voter);
        votes.delegate(_voter(target));
        refDelegate[voter] = _voter(target);
        refWeight[_voter(target)] += vc.balanceOf(voter);
    }

    function _credit(address holder, uint256 amount) internal {
        address d = refDelegate[holder];
        if (d != address(0)) refWeight[d] += amount;
    }

    function _debit(address holder, uint256 amount) internal {
        address d = refDelegate[holder];
        if (d != address(0)) refWeight[d] -= amount;
    }

    function _proposeAndActivate() internal returns (uint256 proposalId) {
        address[] memory targets = new address[](1);
        targets[0] = address(vault);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(IVaultCore.setStrategyManager, (address(0xBEEF)));
        vm.prank(_voter(0));
        proposalId = gov.propose(targets, values, calldatas, "counting fuzz");
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Active), "proposal active");
    }

    /// @dev Casts one ballot and mirrors it into the reference; a counted ballot can never be cast twice.
    function _cast(uint256 proposalId, address voter, uint8 ballot) internal {
        if (ballot == 3) return;
        if (ballot == 4) {
            vm.prank(voter);
            vm.expectRevert(IGovernor.GovernorInvalidVoteType.selector);
            gov.castVote(proposalId, 3);
            assertFalse(gov.hasVoted(proposalId, voter), "invalid ballot not recorded");
            return;
        }

        vm.prank(voter);
        uint256 weight = gov.castVote(proposalId, ballot);
        assertEq(weight, refWeight[voter], "ballot weight = balances delegated to the voter");
        refTally[ballot] += weight;
        assertTrue(gov.hasVoted(proposalId, voter), "ballot recorded");

        vm.prank(voter);
        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorAlreadyCastVote.selector, voter));
        gov.castVote(proposalId, ballot);
    }

    function _voter(uint256 i) internal pure returns (address) {
        return address(uint160(0xC0FFEE00 + i));
    }
}
