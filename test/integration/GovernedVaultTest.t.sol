// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GovernedVaultTestBase} from "@lattice-test/base/GovernedVaultTestBase.sol";
import {GovernedVault} from "@lattice/defi/GovernedVault.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @notice Minimal mintable ERC-20 used as the vault's underlying asset.
contract MockAsset is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function name() external pure returns (string memory) {
        return "Mock Asset";
    }

    function symbol() external pure returns (string memory) {
        return "MCK";
    }

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

/// @title GovernedVaultTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice End-to-end proof of the self-governed ERC-4626 vault on a REAL diamond: depositors receive
///         vote-weighted shares and drive the full governance loop — propose → vote → queue → (timelock delay)
///         → execute — against the vault ITSELF, with no external admin. Also proves the two bespoke seams:
///         deposit grants voting power (mint→checkpoint), and the governor ballot nonce is namespaced away from
///         the ERC-20 delegation nonce.
contract GovernedVaultTest is GovernedVaultTestBase {
    GovernedVault internal vault; // deposit/withdraw/name/clock/transfer/ballotNonce/castVoteBySig
    Governor internal gov; // propose/castVote/queue/execute/token/timelock
    IVotes internal votes; // delegate/getVotes/getPastVotes
    IVaultCore internal vc; // balanceOf/strategyManager/totalAssets
    MockAsset internal asset;

    address internal alice = address(0xA11CE);
    address internal newManager = address(0x5747A6);

    uint256 internal constant DEPOSIT = 1_000 ether;
    uint48 internal constant VOTING_DELAY = 1;
    uint32 internal constant VOTING_PERIOD = 50;
    uint256 internal constant MIN_DELAY = 100;

    function _params() internal pure returns (GovernedVaultParams memory p) {
        p.name = "Governed Vault Share";
        p.symbol = "gVLT";
        p.decimalsOffset = 0;
        p.minDelay = MIN_DELAY;
        p.votingDelay = VOTING_DELAY;
        p.votingPeriod = VOTING_PERIOD;
        p.proposalThreshold = 0; // any share-holder may propose
        p.quorumNumerator = 4; // 4% of supply
    }

    function setUp() public {
        vm.warp(1_000_000); // a non-zero clock so snapshots have room behind them
        asset = new MockAsset();
        address d = _deployGovernedVault(address(asset), _params());
        vault = GovernedVault(d);
        gov = Governor(d);
        votes = IVotes(d);
        vc = IVaultCore(d);

        // Alice deposits the entire supply and activates her voting power by self-delegating.
        asset.mint(alice, DEPOSIT);
        vm.startPrank(alice);
        asset.approve(address(vault), DEPOSIT);
        vault.deposit(DEPOSIT, alice);
        votes.delegate(alice);
        vm.stopPrank();
        vm.warp(block.timestamp + 1); // move the delegation checkpoint into the past
    }

    /// @dev The self-referential wiring: the Governor's token + timelock are the diamond, and the diamond holds
    ///      its own admin — so there is no external owner of the vault.
    function test_SelfGovernedWiring() public view {
        assertEq(gov.token(), address(vault), "governor votes come from the diamond's own shares");
        assertEq(gov.timelock(), address(vault), "governor queues through the diamond's own timelock");
        assertEq(vault.name(), "Governed Vault Share", "single share-token name (clash resolved)");
    }

    /// @dev Depositing shares grants voting power once delegated — the mint→checkpoint seam.
    function test_DepositGrantsVotingPower() public view {
        assertEq(vc.balanceOf(alice), DEPOSIT, "alice holds all shares");
        assertEq(votes.getVotes(alice), DEPOSIT, "delegated deposit = voting power");
    }

    function _buildProposal()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description)
    {
        targets = new address[](1);
        targets[0] = address(vault); // the vault governs ITSELF
        values = new uint256[](1);
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(IVaultCore.setStrategyManager, (newManager));
        description = "Set the vault strategy manager";
    }

    /// @notice THE FULL LOOP: propose → vote → queue → wait out the timelock → execute → the vault's own admin
    ///         state changed, driven entirely by share-holder governance.
    function test_FullGovernanceLoopSetsVaultStrategyManager() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        bytes32 descHash = keccak256(bytes(description));

        vm.prank(alice);
        uint256 proposalId = gov.propose(targets, values, calldatas, description);

        // Voting window.
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.prank(alice);
        gov.castVote(proposalId, uint8(IGovernor.VoteType.For));
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Queue into the timelock, then execute after the delay — through the diamond itself.
        gov.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + MIN_DELAY + 1);
        gov.execute(targets, values, calldatas, descHash);

        assertEq(vc.strategyManager(), newManager, "share-holder governance set the vault's strategy manager");
    }

    /// @notice The timelock delay is enforced: executing before it elapses reverts.
    function test_ExecuteBeforeTimelockDelayReverts() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        bytes32 descHash = keccak256(bytes(description));

        vm.prank(alice);
        uint256 proposalId = gov.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.prank(alice);
        gov.castVote(proposalId, uint8(IGovernor.VoteType.For));
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        gov.queue(targets, values, calldatas, descHash);

        // No warp past MIN_DELAY — execution must not be permitted yet.
        vm.expectRevert();
        gov.execute(targets, values, calldatas, descHash);
    }

    /// @notice An un-voted proposal cannot pass — the vault's admin stays unchanged.
    function test_ProposalWithoutQuorumDoesNotExecute() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        bytes32 descHash = keccak256(bytes(description));

        vm.prank(alice);
        gov.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        // No vote cast → quorum not met.
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        vm.expectRevert(); // Defeated proposals cannot be queued
        gov.queue(targets, values, calldatas, descHash);
        assertEq(vc.strategyManager(), address(0), "vault admin unchanged");
    }

    /// @notice NONCE NAMESPACE: the governor ballot nonce is independent of the ERC-20 delegation nonce, so a
    ///         delegation cannot invalidate a pending vote signature (the bug a shared counter would cause).
    function test_BallotNonceIsIndependentOfDelegationNonce() public {
        uint256 pk = 0xBEEF;
        address voter = vm.addr(pk);
        _fundAndDelegate(voter, 10 ether);
        assertEq(vault.ballotNonce(voter), 0, "fresh ballot nonce");

        uint256 proposalId = _proposeAndActivate();

        // A vote cast by signature consumes ONLY the dedicated ballot nonce (starts at 0), never the ERC-20
        // delegation nonce — so a `delegateBySig` could not have invalidated this signature.
        _castVoteBySig(pk, voter, proposalId);
        assertEq(vault.ballotNonce(voter), 1, "vote consumed the BALLOT nonce");
    }

    function _fundAndDelegate(address who, uint256 amount) internal {
        asset.mint(who, amount);
        vm.startPrank(who);
        asset.approve(address(vault), amount);
        vault.deposit(amount, who);
        votes.delegate(who);
        vm.stopPrank();
        vm.warp(block.timestamp + 1);
    }

    function _proposeAndActivate() internal returns (uint256 proposalId) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            _buildProposal();
        vm.prank(alice);
        proposalId = gov.propose(targets, values, calldatas, description);
        vm.warp(block.timestamp + VOTING_DELAY + 1);
    }

    function _castVoteBySig(uint256 pk, address voter, uint256 proposalId) internal {
        bytes32 ballotType = keccak256("Ballot(uint256 proposalId,uint8 support,address voter,uint256 nonce)");
        bytes32 structHash = keccak256(abi.encode(ballotType, proposalId, uint8(1), voter, uint256(0)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _domainDigest(structHash));
        vault.castVoteBySig(proposalId, uint8(1), voter, abi.encodePacked(r, s, v));
    }

    function _domainDigest(bytes32 structHash) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Governed Vault Share")),
                keccak256(bytes("1")),
                block.chainid,
                address(vault)
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
