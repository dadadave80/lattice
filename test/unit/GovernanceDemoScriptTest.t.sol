// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVaultENS, TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {GovernedVaultENSParams} from "@lattice/defi/GovernedVaultENSInit.sol";
import {IReverseRegistrar} from "@lattice/interfaces/external/IReverseRegistrar.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {Test} from "forge-std/Test.sol";

/// @title DemoMockReverseRegistrar
/// @notice Minimal ENS reverse registrar recording the name each caller sets plus a call counter (the
///        {GovernedVaultENSInitTest} fixture pattern).
contract DemoMockReverseRegistrar is IReverseRegistrar {
    mapping(address caller => string name) public nameOf;
    uint256 public setNameCalls;

    function setName(string memory name) external {
        nameOf[msg.sender] = name;
        ++setNameCalls;
    }
}

/// @title MockWeth9Asset
/// @notice WETH9-pattern underlying: NO `mint(address,uint256)` selector and a non-reverting payable
///         fallback that swallows unknown calls — the exact shape that makes an unguarded faucet mint
///         "succeed" while crediting nothing.
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

/// @title GovernanceDemoScriptTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Drives {DeployGovernedVaultENS.governanceDemoStep} — the self-cranking post-deploy governance
///         runbook — through the FULL lifecycle on a real 14-cut vault diamond: crank 1 dogfoods
///         (mint/approve/deposit/delegate) and proposes; crank 2 (past votingDelay) votes For; crank 3
///         (past votingPeriod) queues; crank 4 (past minDelay) executes the combined freeze+rename payload;
///         further cranks are harmless no-ops. The ACTOR here is the script contract instance itself —
///         without a broadcast, the step's sub-calls originate from it, exactly why the step takes an
///         explicit `actor` (the broadcast wrapper passes `msg.sender`, the keystore signer, instead).
contract GovernanceDemoScriptTest is Test {
    DeployGovernedVaultENS internal deployer;
    DemoMockReverseRegistrar internal registrar;
    TestnetAsset internal asset;

    address internal vault;
    address internal actor; // the script instance — the sender of every broadcast-free sub-call

    string internal constant ENS_NAME = "milestone1vault.lattice.studio.eth";

    function setUp() public {
        vm.warp(1_000_000); // non-zero timestamp clock so checkpoints have room behind them
        registrar = new DemoMockReverseRegistrar();
        asset = new TestnetAsset("Lattice Testnet Asset", "tLAT");
        deployer = new DeployGovernedVaultENS();
        actor = address(deployer);

        GovernedVaultENSParams memory p;
        p.vault.asset = address(asset);
        p.vault.name = "Governed Vault Share";
        p.vault.symbol = "gVLT";
        p.vault.minDelay = 300;
        p.vault.votingDelay = 60;
        p.vault.votingPeriod = 600;
        p.vault.quorumNumerator = 4;
        p.reverseRegistrar = address(registrar);
        p.ensName = ENS_NAME;

        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCutsWithENS(p);
        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        vault = address(d);
    }

    function _frozenSix() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](6);
        s[0] = IDiamondLoupe.facets.selector;
        s[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        s[2] = IDiamondLoupe.facetAddresses.selector;
        s[3] = IDiamondLoupe.facetAddress.selector;
        s[4] = IGovernedDiamondCut.diamondCut.selector;
        s[5] = IEmergencyCut.emergencyRemoveCut.selector;
    }

    /// @notice The whole runbook, one crank per state, exactly as the Sepolia operator re-runs it.
    function test_CrankLifecycleExecutesFreezeAndRename() public {
        uint256 pid = deployer.demoProposalId(vault, ENS_NAME);

        // Crank 1 — nonexistent proposal: dogfood (mint/approve/deposit/delegate) then propose.
        deployer.governanceDemoStep(vault, ENS_NAME, actor);
        assertEq(IERC20(vault).balanceOf(actor), 1_000e18, "crank 1 deposits the dogfood stake");
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
        assertEq(registrar.nameOf(vault), ENS_NAME, "reverse record re-asserted by the proposal");
        assertEq(registrar.setNameCalls(), 2, "exactly the init claim + the governed re-assert");

        // Crank 5 — Executed: a harmless no-op.
        deployer.governanceDemoStep(vault, ENS_NAME, actor);
        assertEq(registrar.setNameCalls(), 2, "re-crank on Executed changes nothing");
    }

    /// @notice A second crank while the vote is Active must not double-vote (and must not revert).
    function test_DoubleCrankDuringActiveDoesNotDoubleVote() public {
        deployer.governanceDemoStep(vault, ENS_NAME, actor); // dogfood + propose
        vm.warp(block.timestamp + 61);
        deployer.governanceDemoStep(vault, ENS_NAME, actor); // votes
        uint256 pid = deployer.demoProposalId(vault, ENS_NAME);
        assertTrue(IGovernor(vault).hasVoted(pid, actor), "voted once");

        deployer.governanceDemoStep(vault, ENS_NAME, actor); // still Active: must be a no-op, not a revert
        assertTrue(IGovernor(vault).hasVoted(pid, actor), "still exactly one ballot");
    }

    /// @notice TESTNET-ONLY guard: against a WETH9-pattern underlying (no faucet, swallowing fallback) the
    ///         dogfood crank reverts BEFORE approve/deposit — the funded operator's real tokens never move.
    function test_CrankRevertsOnNonFaucetAssetWithoutPullingFunds() public {
        MockWeth9Asset weth = new MockWeth9Asset(actor, 5_000e18);

        GovernedVaultENSParams memory p;
        p.vault.asset = address(weth);
        p.vault.name = "Real Asset Vault Share";
        p.vault.symbol = "rVLT";
        p.vault.minDelay = 300;
        p.vault.votingDelay = 60;
        p.vault.votingPeriod = 600;
        p.vault.quorumNumerator = 4;
        p.reverseRegistrar = address(registrar);
        p.ensName = ENS_NAME;
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCutsWithENS(p);
        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        address realVault = address(d);

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

    /// @notice The BROADCAST WRAPPER itself (the runbook command) passes ITS CALLER as the actor: with
    ///         this test contract pre-funded and pre-delegated, the wrapper's first crank SKIPS dogfooding
    ///         (the actor checks see the caller's shares) and goes straight to propose. The mutant —
    ///         `governanceDemo` passing `address(this)` (the script instance, balance 0) instead of
    ///         `msg.sender` — takes the dogfood path instead and reverts `SafeERC20FailedOperation`
    ///         (mint lands on the instance, the deposit pulls from the unfunded broadcast sender), so this
    ///         test discriminates the two (mutant-proven red during review fixing).
    /// @dev Environment note (empirical): in a test, no-arg `startBroadcast()` sends sub-calls from
    ///      `tx.origin` (forge-std DEFAULT_SENDER) while the wrapper's `msg.sender` is this test contract,
    ///      and `vm.prank` cannot align them (pranks and broadcasts are mutually exclusive). Under the CLI
    ///      the two coincide in the keystore signer. The sender-aligned full lifecycle is covered through
    ///      `governanceDemoStep`; THIS test pins the wrapper's actor plumbing.
    function test_GovernanceDemoWrapperActsForItsCaller() public {
        // Pre-fund + delegate THE WRAPPER'S CALLER (this test contract) — the real-vault operator flow.
        asset.mint(address(this), 1_000e18);
        asset.approve(vault, 1_000e18);
        IERC4626(vault).deposit(1_000e18, address(this));
        IVotes(vault).delegate(address(this));

        // Correct wrapper: actor = msg.sender = this (funded) -> dogfood skipped -> propose only.
        deployer.governanceDemo(vault, ENS_NAME);

        uint256 pid = deployer.demoProposalId(vault, ENS_NAME);
        assertEq(uint8(IGovernor(vault).state(pid)), uint8(IGovernor.ProposalState.Pending), "proposal created");
        assertEq(IERC20(vault).balanceOf(address(this)), 1_000e18, "caller stake untouched");
        assertEq(IERC20(vault).balanceOf(address(deployer)), 0, "script instance was never dogfooded");
        assertEq(IERC20(vault).totalSupply(), 1_000e18, "no phantom dogfood deposit happened");
    }
}
