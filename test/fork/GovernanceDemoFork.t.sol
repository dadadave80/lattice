// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVaultENS, TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {GovernedVault} from "@lattice/defi/GovernedVault.sol";
import {GovernedVaultENSParams} from "@lattice/defi/GovernedVaultENSInit.sol";
import {ENSReverseClaimer} from "@lattice/ens/ENSReverseClaimer.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {IENS} from "@lattice/interfaces/external/ens/IENS.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Reverse-node reads on the REAL Sepolia ReverseRegistrar (`node(addr)` is pure upstream).
interface IReverseRegistrarNode {
    function node(address addr) external pure returns (bytes32);
}

/// @notice ENS name-resolver read used to resolve the claimed reverse record on the fork.
interface INameResolver {
    function name(bytes32 node) external view returns (string memory);
}

/// @title MockWeth9Asset
/// @notice WETH9-pattern underlying (allowed: the no-mock rule is about the ENS REGISTRAR only): NO
///         `mint(address,uint256)` selector and a non-reverting payable fallback that swallows unknown
///         calls — the shape that makes an unguarded faucet mint "succeed" while crediting nothing.
contract MockWeth9Asset {
    string public name = "Wrapped Mock";
    string public symbol = "WMOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address account => uint256) public balanceOf;
    mapping(address owner => mapping(address spender => uint256)) public allowance;

    constructor(address funded, uint256 amount) {
        balanceOf[funded] = amount;
        totalSupply = amount;
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

    fallback() external payable {} // swallows mint(address,uint256) without reverting

    receive() external payable {}
}

/// @notice Exposes {DeployGovernedVaultENS}'s internal status/attempt computation so tests assert the
///         parsed `(state, waitSeconds, done, attempt)` values directly instead of scraping console output
///         (the {RegisterEnsNameProbe} idiom). Stateless over `vault`, so one probe serves any vault.
contract GovernanceDemoProbe is DeployGovernedVaultENS {
    function status(address vault, string calldata ensName, address actor)
        external
        view
        returns (uint8 state, uint256 waitSeconds, uint256 done, uint256 attempt)
    {
        return _demoStatus(vault, ensName, actor);
    }

    function activeAttempt(address vault, string calldata ensName) external view returns (uint256) {
        return _activeAttempt(vault, ensName);
    }
}

/// @title GovernanceDemoFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Sepolia FORK proof of the {DeployGovernedVaultENS} self-cranking governance runbook against the
///         REAL ENS deployment (no registrar mock): the demo crank drives a 14-cut vault diamond
///         propose -> vote -> queue -> execute over the LIVE {ReverseRegistrar}, and shareholder governance
///         re-sets the diamond's primary reverse record on-chain — the definitive proof a registrar mock
///         cannot give. Mirrors the harness of {GovernedVaultENSFork}.
///
/// Enabling this test:
///   export SEPOLIA_RPC_URL=<your-sepolia-rpc-url>
///   forge test --match-path "test/fork/GovernanceDemoFork.t.sol"
///
/// The test is skipped cleanly when SEPOLIA_RPC_URL is unset.
contract GovernanceDemoFork is Test {
    //*//////////////////////////////////////////////////////////////////////////
    //             VERIFIED SEPOLIA ADDRESSES (ensdomains/ens-contracts)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ENS registry (deployments/sepolia/ENSRegistry.json).
    address internal constant SEPOLIA_ENS_REGISTRY = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;

    /// @notice ENS reverse registrar (deployments/sepolia/ReverseRegistrar.json).
    address internal constant SEPOLIA_REVERSE_REGISTRAR = 0xA0a1AbcDAe1a2a4A2EF8e9113Ff0e02DD81DC0C6;

    /// @notice A recent Sepolia block; overridable via SEPOLIA_FORK_BLOCK for a fresher value. Pinned so runs
    ///         are reproducible and forge's RPC cache actually hits (matches the other fork suites).
    uint256 internal constant DEFAULT_FORK_BLOCK = 11_239_288;

    string internal constant ENS_NAME = "milestone1vault.lattice.studio.eth";
    string internal constant RENAMED = "renamed.milestone1vault.lattice.studio.eth";

    uint48 internal constant VOTING_DELAY = 60; // seconds (timestamp clock)
    uint32 internal constant VOTING_PERIOD = 600; // seconds (timestamp clock)
    uint256 internal constant MIN_DELAY = 300; // seconds
    uint256 internal constant DEPOSIT = 1_000 ether;

    DeployGovernedVaultENS internal deployer;
    GovernanceDemoProbe internal probe;
    TestnetAsset internal asset;
    address internal vault;
    address internal actor; // the script instance — the sender of every broadcast-free crank sub-call

    address internal alice = address(0xA11CE);

    function _params(address asset_, string memory ensName_) internal view returns (GovernedVaultENSParams memory p) {
        p.vault.asset = asset_;
        p.vault.name = "Governed Vault Share";
        p.vault.symbol = "gVLT";
        p.vault.decimalsOffset = 0;
        p.vault.minDelay = MIN_DELAY;
        p.vault.votingDelay = VOTING_DELAY;
        p.vault.votingPeriod = VOTING_PERIOD;
        p.vault.proposalThreshold = 0;
        p.vault.quorumNumerator = 4;
        p.reverseRegistrar = SEPOLIA_REVERSE_REGISTRAR;
        p.ensName = ensName_;
    }

    function _deploy(address asset_, string memory ensName_) internal returns (address diamond_) {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            deployer.buildCutsWithENS(_params(asset_, ensName_));
        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }

    function setUp() public {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("sepolia", vm.envOr("SEPOLIA_FORK_BLOCK", DEFAULT_FORK_BLOCK));

        asset = new TestnetAsset("Lattice Testnet Asset", "tLAT");
        deployer = new DeployGovernedVaultENS();
        probe = new GovernanceDemoProbe();
        actor = address(deployer);
        vault = _deploy(address(asset), ENS_NAME);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    function _frozenSix() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](6);
        s[0] = IDiamondLoupe.facets.selector;
        s[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        s[2] = IDiamondLoupe.facetAddresses.selector;
        s[3] = IDiamondLoupe.facetAddress.selector;
        s[4] = IGovernedDiamondCut.diamondCut.selector;
        s[5] = IEmergencyCut.emergencyRemoveCut.selector;
    }

    /// @dev The live reverse record the diamond resolves to, read through the REAL ENS registry.
    function _liveReverseName(address diamond) internal view returns (string memory) {
        bytes32 node = IReverseRegistrarNode(SEPOLIA_REVERSE_REGISTRAR).node(diamond);
        address resolver = IENS(SEPOLIA_ENS_REGISTRY).resolver(node);
        assertTrue(resolver != address(0), "reverse node claimed with the registrar's default resolver");
        return INameResolver(resolver).name(node);
    }

    function _depositAndDelegate(address who, uint256 amount) internal {
        asset.mint(who, amount);
        vm.startPrank(who);
        asset.approve(vault, amount);
        IERC4626(vault).deposit(amount, who);
        IVotes(vault).delegate(who);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          DEMO CRANK LIFECYCLE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The whole runbook, one crank per state, over the LIVE registrar — the same test the unit
    ///         suite used to run against a mock, now proving the reverse record survives the same-name
    ///         re-assert on real ENS.
    function test_Fork_CrankLifecycleExecutesFreezeAndRename() public {
        uint256 pid = deployer.demoProposalId(vault, ENS_NAME);

        // Crank 1 — nonexistent proposal: dogfood then propose.
        deployer.governanceDemoStep(vault, ENS_NAME, actor);
        assertEq(IERC20(vault).balanceOf(actor), DEPOSIT, "crank 1 deposits the dogfood stake");
        assertEq(IVotes(vault).delegates(actor), actor, "crank 1 self-delegates");
        assertEq(uint8(IGovernor(vault).state(pid)), uint8(IGovernor.ProposalState.Pending), "proposal created");

        // Crank 2 — Active: casts the For vote.
        vm.warp(block.timestamp + 61);
        deployer.governanceDemoStep(vault, ENS_NAME, actor);
        assertTrue(IGovernor(vault).hasVoted(pid, actor), "crank 2 votes For");

        // Crank 3 — Succeeded: queues into the vault's own timelock.
        vm.warp(block.timestamp + 601);
        deployer.governanceDemoStep(vault, ENS_NAME, actor);
        assertEq(uint8(IGovernor(vault).state(pid)), uint8(IGovernor.ProposalState.Queued), "crank 3 queues");

        // Crank 4 — Queued past eta: executes freeze + rename in one proposal.
        vm.warp(block.timestamp + 301);
        deployer.governanceDemoStep(vault, ENS_NAME, actor);
        assertEq(uint8(IGovernor(vault).state(pid)), uint8(IGovernor.ProposalState.Executed), "crank 4 executes");

        bytes4[] memory six = _frozenSix();
        for (uint256 i; i < six.length; ++i) {
            assertTrue(IFrozenSelectors(vault).isSelectorFrozen(six[i]), "loupe/cut/emergency selector frozen");
        }
        // The proposal re-asserted the SAME name; the LIVE reverse record still resolves to it.
        assertEq(_liveReverseName(vault), ENS_NAME, "same-name governed re-assert kept the live reverse record");
        assertEq(ENSReverseClaimer(vault).ensName(), ENS_NAME, "facet cache matches the live record");

        // Crank 5 — Executed: a harmless no-op.
        deployer.governanceDemoStep(vault, ENS_NAME, actor);
        assertEq(_liveReverseName(vault), ENS_NAME, "re-crank on Executed changes nothing");
    }

    /// @notice A second crank while the vote is Active must not double-vote (and must not revert).
    function test_Fork_DoubleCrankDuringActiveDoesNotDoubleVote() public {
        deployer.governanceDemoStep(vault, ENS_NAME, actor); // dogfood + propose
        vm.warp(block.timestamp + 61);
        deployer.governanceDemoStep(vault, ENS_NAME, actor); // votes
        uint256 pid = deployer.demoProposalId(vault, ENS_NAME);
        assertTrue(IGovernor(vault).hasVoted(pid, actor), "voted once");

        deployer.governanceDemoStep(vault, ENS_NAME, actor); // still Active: must be a no-op, not a revert
        assertTrue(IGovernor(vault).hasVoted(pid, actor), "still exactly one ballot");
    }

    /// @notice TESTNET-ONLY guard: against a WETH9-pattern underlying the dogfood crank reverts BEFORE
    ///         approve/deposit — the funded operator's real tokens never move. (Registrar is the LIVE one;
    ///         only the ASSET is a mock, which the no-mock rule permits.)
    function test_Fork_CrankRevertsOnNonFaucetAssetWithoutPullingFunds() public {
        MockWeth9Asset weth = new MockWeth9Asset(actor, 5_000e18);
        address realVault = _deploy(address(weth), ENS_NAME);

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployGovernedVaultENS.DeployGovernedVaultENS__AssetNotOpenFaucet.selector, address(weth)
            )
        );
        deployer.governanceDemoStep(realVault, ENS_NAME, actor);

        assertEq(weth.balanceOf(actor), 5_000e18, "not one real token pulled");
        assertEq(weth.allowance(actor, realVault), 0, "no approval left behind");
        assertEq(IERC20(realVault).balanceOf(actor), 0, "no phantom shares");
    }

    /// @notice The BROADCAST WRAPPER passes ITS CALLER as the actor: pre-funded + pre-delegated, the
    ///         wrapper's first crank SKIPS dogfooding and proposes. The mutant (`governanceDemo` passing
    ///         `address(this)` instead of `msg.sender`) dogfoods the script instead and reverts
    ///         `SafeERC20FailedOperation` (mint lands on the instance, deposit pulls from the unfunded
    ///         broadcast sender) — proven red during review.
    /// @dev In a test, no-arg `startBroadcast()` sends sub-calls from `tx.origin` (forge-std DEFAULT_SENDER)
    ///      while the wrapper's `msg.sender` is this test contract, and `vm.prank` cannot align them. Under
    ///      the CLI the two coincide in the keystore signer. The sender-aligned full lifecycle is covered
    ///      through `governanceDemoStep`; THIS test pins the wrapper's actor plumbing.
    function test_Fork_GovernanceDemoWrapperActsForItsCaller() public {
        asset.mint(address(this), DEPOSIT);
        asset.approve(vault, DEPOSIT);
        IERC4626(vault).deposit(DEPOSIT, address(this));
        IVotes(vault).delegate(address(this));

        deployer.governanceDemo(vault, ENS_NAME);

        uint256 pid = deployer.demoProposalId(vault, ENS_NAME);
        assertEq(uint8(IGovernor(vault).state(pid)), uint8(IGovernor.ProposalState.Pending), "proposal created");
        assertEq(IERC20(vault).balanceOf(address(this)), DEPOSIT, "caller stake untouched");
        assertEq(IERC20(vault).balanceOf(address(deployer)), 0, "script instance was never dogfooded");
        assertEq(IERC20(vault).totalSupply(), DEPOSIT, "no phantom dogfood deposit happened");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                LIVE GOVERNED RENAME — the mock could not prove this
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The definitive proof: a bespoke shareholder proposal whose single action is the diamond's
    ///         `setEnsName` to a DIFFERENT name, driven propose -> vote -> queue -> execute, RE-SETS the
    ///         diamond's LIVE primary reverse record on real Sepolia ENS — read back through the real
    ///         registry (node -> resolver -> name).
    function test_Fork_GovernanceRenamesLiveReverseRecord() public {
        // The init-time claim already set the live record to ENS_NAME.
        assertEq(_liveReverseName(vault), ENS_NAME, "init claim resolves live before the rename");

        // A voter with 100% of supply (past the 4% quorum), checkpointed behind the snapshot.
        _depositAndDelegate(alice, DEPOSIT);
        vm.warp(block.timestamp + 1);

        address[] memory targets = new address[](1);
        targets[0] = vault;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(ENSReverseClaimer.setEnsName, (RENAMED));
        string memory description = "Rename the vault's primary ENS name through shareholder governance";
        bytes32 descriptionHash = keccak256(bytes(description));

        vm.prank(alice);
        uint256 pid = Governor(vault).propose(targets, values, calldatas, description);

        vm.warp(block.timestamp + 61); // past votingDelay
        vm.prank(alice);
        Governor(vault).castVote(pid, uint8(IGovernor.VoteType.For));

        vm.warp(block.timestamp + 601); // past votingPeriod
        Governor(vault).queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + 301); // past minDelay
        Governor(vault).execute(targets, values, calldatas, descriptionHash);

        assertEq(uint8(Governor(vault).state(pid)), uint8(IGovernor.ProposalState.Executed), "rename executed");
        // THE PROOF: the LIVE reverse record now resolves to the NEW name, set by governance alone.
        assertEq(_liveReverseName(vault), RENAMED, "governance re-set the live primary name on-chain");
        assertEq(ENSReverseClaimer(vault).ensName(), RENAMED, "facet cache matches the live rename");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //              RETRY DISAMBIGUATION — the un-brick proof
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice THE proof the deterministic-id brick is fixed: an attempt that DEFEATS (its vote window
    ///         missed) no longer dead-ends the crank — the next crank self-heals onto a fresh attempt id,
    ///         which then drives all the way to Executed on the LIVE registrar.
    function test_Fork_DemoRecoversFromDefeatedAttempt() public {
        // Attempt 0: dogfood + propose.
        deployer.governanceDemoStep(vault, ENS_NAME, actor);
        uint256 pid0 = deployer.demoProposalId(vault, ENS_NAME, 0);
        assertEq(uint8(IGovernor(vault).state(pid0)), uint8(IGovernor.ProposalState.Pending), "attempt 0 pending");

        // Miss the ENTIRE voting window without voting -> quorum unmet -> Defeated (the live brick trigger).
        vm.warp(block.timestamp + 61 + 601);
        assertEq(uint8(IGovernor(vault).state(pid0)), uint8(IGovernor.ProposalState.Defeated), "attempt 0 defeated");

        // Self-heal: the next crank proposes a FRESH id (attempt 1), not a collision on the dead one.
        deployer.governanceDemoStep(vault, ENS_NAME, actor);
        uint256 pid1 = deployer.demoProposalId(vault, ENS_NAME, 1);
        assertTrue(pid1 != pid0, "retry mints a fresh proposal id");
        assertEq(deployer.demoProposalId(vault, ENS_NAME), pid1, "active attempt advanced to 1");
        assertEq(probe.activeAttempt(vault, ENS_NAME), 1, "active attempt index is 1");
        assertEq(uint8(IGovernor(vault).state(pid1)), uint8(IGovernor.ProposalState.Pending), "attempt 1 pending");
        assertEq(
            uint8(IGovernor(vault).state(pid0)), uint8(IGovernor.ProposalState.Defeated), "attempt 0 stays defeated"
        );

        // Drive attempt 1 through vote -> queue -> execute via the crank (the operator votes IN TIME now).
        vm.warp(block.timestamp + 61);
        deployer.governanceDemoStep(vault, ENS_NAME, actor); // votes attempt 1
        assertTrue(IGovernor(vault).hasVoted(pid1, actor), "voted attempt 1");
        vm.warp(block.timestamp + 601);
        deployer.governanceDemoStep(vault, ENS_NAME, actor); // queues
        vm.warp(block.timestamp + 301);
        deployer.governanceDemoStep(vault, ENS_NAME, actor); // executes
        assertEq(uint8(IGovernor(vault).state(pid1)), uint8(IGovernor.ProposalState.Executed), "attempt 1 executed");

        // Same outcome as a first-try success: six selectors frozen, ENS reasserted on the LIVE registry.
        bytes4[] memory six = _frozenSix();
        for (uint256 i; i < six.length; ++i) {
            assertTrue(IFrozenSelectors(vault).isSelectorFrozen(six[i]), "selector frozen after recovery");
        }
        assertEq(_liveReverseName(vault), ENS_NAME, "ENS reasserted via the recovered attempt");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                 MACHINE-READABLE STATUS — per-phase values
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The read-only status computation reports the correct (state, wait, done, attempt) at every
    ///         phase — the values the external autonomous loop parses to decide crank-vs-sleep.
    function test_Fork_StatusMatchesEachPhase() public {
        // Nonexistent -> sentinel 8, actionable now, attempt 0.
        (uint8 state, uint256 wait, uint256 done, uint256 attempt) = probe.status(vault, ENS_NAME, actor);
        assertEq(state, 8, "nonexistent sentinel");
        assertEq(wait, 0, "nonexistent is actionable (propose)");
        assertEq(done, 0, "not done");
        assertEq(attempt, 0, "attempt 0");

        // Pending -> waits for the snapshot.
        deployer.governanceDemoStep(vault, ENS_NAME, actor);
        (state, wait, done,) = probe.status(vault, ENS_NAME, actor);
        assertEq(state, uint8(IGovernor.ProposalState.Pending), "pending");
        assertGt(wait, 0, "pending waits for the snapshot");
        assertEq(done, 0, "not done");

        // Active, not voted -> actionable now (vote).
        vm.warp(block.timestamp + 61);
        (state, wait,,) = probe.status(vault, ENS_NAME, actor);
        assertEq(state, uint8(IGovernor.ProposalState.Active), "active");
        assertEq(wait, 0, "active-not-voted is actionable (vote)");

        // Active, voted -> waits for the deadline.
        deployer.governanceDemoStep(vault, ENS_NAME, actor);
        (state, wait,,) = probe.status(vault, ENS_NAME, actor);
        assertEq(state, uint8(IGovernor.ProposalState.Active), "active after voting");
        assertGt(wait, 0, "active-voted waits for the deadline");

        // Queued, not ready -> waits for the timelock eta.
        vm.warp(block.timestamp + 601);
        deployer.governanceDemoStep(vault, ENS_NAME, actor);
        (state, wait,,) = probe.status(vault, ENS_NAME, actor);
        assertEq(state, uint8(IGovernor.ProposalState.Queued), "queued");
        assertGt(wait, 0, "queued waits for the eta");

        // Executed -> done.
        vm.warp(block.timestamp + 301);
        deployer.governanceDemoStep(vault, ENS_NAME, actor);
        (state, wait, done,) = probe.status(vault, ENS_NAME, actor);
        assertEq(state, uint8(IGovernor.ProposalState.Executed), "executed");
        assertEq(wait, 0, "executed needs nothing");
        assertEq(done, 1, "done");

        // After a Defeated attempt on a fresh vault, status points at the fresh attempt as actionable.
        address v2 = _deploy(address(asset), ENS_NAME);
        deployer.governanceDemoStep(v2, ENS_NAME, actor); // propose attempt 0
        vm.warp(block.timestamp + 61 + 601); // miss the window -> Defeated
        (state, wait, done, attempt) = probe.status(v2, ENS_NAME, actor);
        assertEq(state, 8, "defeated -> active attempt is the fresh nonexistent one");
        assertEq(wait, 0, "fresh attempt is actionable (propose)");
        assertEq(done, 0, "not done");
        assertEq(attempt, 1, "advanced past the defeated attempt");
    }
}
