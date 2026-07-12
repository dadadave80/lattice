// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {GovernedVaultENSInit, GovernedVaultENSParams} from "@lattice/defi/GovernedVaultENSInit.sol";
import {ENSReverseClaimer} from "@lattice/ens/ENSReverseClaimer.sol";
import {IENSReverseClaimer} from "@lattice/interfaces/ens/IENSReverseClaimer.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {console} from "forge-std/Script.sol";

/// @title TestnetAsset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice TESTNET-ONLY open-faucet ERC-20 — anyone may `mint` themselves balance. Deployed by
///         {DeployGovernedVaultENS.run} as the vault's underlying when no real asset is supplied, so the
///         Sepolia dogfooding loop (mint → approve → deposit → vote) needs no external token. NEVER deploy
///         this to a mainnet: the open faucet makes every balance worthless by construction.
contract TestnetAsset is IERC20 {
    string private _name;
    string private _symbol;

    /// @inheritdoc IERC20
    mapping(address account => uint256 balance) public balanceOf;
    /// @inheritdoc IERC20
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;
    /// @inheritdoc IERC20
    uint256 public totalSupply;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /// @inheritdoc IERC20
    function name() external view returns (string memory) {
        return _name;
    }

    /// @inheritdoc IERC20
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc IERC20
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @notice Open faucet: mints `amount` to `to`, no gate whatsoever (TESTNET-ONLY by design).
    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 value) external returns (bool success) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        success = true;
    }

    /// @inheritdoc IERC20
    function transfer(address to, uint256 value) external returns (bool success) {
        uint256 balance = balanceOf[msg.sender];
        if (balance < value) revert ERC20InsufficientBalance(msg.sender, balance, value);
        balanceOf[msg.sender] = balance - value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        success = true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 value) external returns (bool success) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed < value) revert ERC20InsufficientAllowance(msg.sender, allowed, value);
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - value;
        uint256 balance = balanceOf[from];
        if (balance < value) revert ERC20InsufficientBalance(from, balance, value);
        balanceOf[from] = balance - value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        success = true;
    }
}

/// @title DeployGovernedVaultENS
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for the ENS-NAMED self-governed ERC-4626 vault: the {DeployGovernedVault}
///         13-cut diamond plus the {ENSReverseClaimer} facet, initialized in ONE shot by
///         {GovernedVaultENSInit} — the vault claims its primary ENS name at init (the registrar sees the
///         diamond as `msg.sender`), and every future rename passes through share-holder governance
///         (`ENS_MANAGER_ROLE` is held by the diamond only).
/// @dev SANE SEPOLIA TESTNET DEFAULTS for `GovernedVaultParams` (the {VotesLib} clock is
///      `mode=timestamp`, so `votingDelay`/`votingPeriod` are SECONDS, not blocks):
///      - `asset`             `address(0)` → {run} deploys a fresh {TestnetAsset} faucet as the underlying
///      - `decimalsOffset`    0
///      - `minDelay`          300  (5-minute timelock)
///      - `votingDelay`       60   (1 minute before voting opens)
///      - `votingPeriod`      600  (10-minute voting window)
///      - `proposalThreshold` 0    (any share-holder may propose)
///      - `quorumNumerator`   4    (4% of supply)
///      `reverseRegistrar` on Sepolia is the ENS `ReverseRegistrar`
///      `0xA0a1AbcDAe1a2a4A2EF8e9113Ff0e02DD81DC0C6` (ensdomains/ens-contracts deployments/sepolia).
///
///      RUNBOOK — step 1 deploy (`run`), steps 2-4 wire the ENS forward record as the name owner (see
///      {RegisterEnsName}); step 5 cranks the governance demo — ONE command, re-run until it logs Executed:
///
///        forge script script/base/defi/DeployGovernedVaultENS.s.sol --rpc-url sepolia --account <name> \
///          --broadcast --sig "governanceDemo(address,string)" <vault> "<ens-name>"
///
///      Each re-run performs whatever the proposal state allows next (dogfood+propose -> vote -> queue ->
///      execute) and logs what to wait for (testnet defaults: 60s until the vote opens, 600s until it
///      closes, 300s of timelock). The proposal freezes the six load-bearing selectors and re-asserts the
///      vault's ENS name — all through shareholder governance.
contract DeployGovernedVaultENS is DeployGovernedVault {
    /// @notice Thrown when the dogfood path's faucet mint did not credit the stake: the vault's underlying
    ///         is not the open-faucet {TestnetAsset} (e.g. a WETH9-pattern token whose non-reverting
    ///         fallback swallows the phantom `mint` call). Reverting HERE prevents the follow-up
    ///         approve+deposit from silently pulling the operator's REAL tokens.
    /// @param asset The vault underlying that failed the faucet probe.
    error DeployGovernedVaultENS__AssetNotOpenFaucet(address asset);

    /// @notice Builds the 14 cuts + combined initializer for the ENS-named self-governed vault (no broadcast,
    ///         no proxy deploy): the inherited 13 base cuts plus the {ENSReverseClaimer} facet, initialized by
    ///         the combined {GovernedVaultENSInit} (which replays the base init sequence exactly).
    function buildCutsWithENS(GovernedVaultENSParams memory p)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        FacetCut[] memory baseCuts = _buildBaseCuts();
        cuts = new FacetCut[](baseCuts.length + 1);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        cuts[baseCuts.length] = _cut(address(new ENSReverseClaimer()));

        init = address(new GovernedVaultENSInit());
        initCalldata = abi.encodeCall(GovernedVaultENSInit.init, (p));
    }

    /// @notice Deploys the ENS-named self-governed vault diamond (broadcasting entrypoint for
    ///         `forge script ... --broadcast`). A zero `p.vault.asset` deploys a fresh {TestnetAsset} faucet
    ///         as the underlying (Sepolia dogfooding).
    function run(GovernedVaultENSParams memory p) external returns (address vault) {
        vm.startBroadcast();
        if (p.vault.asset == address(0)) {
            p.vault.asset = address(new TestnetAsset("Lattice Testnet Asset", "tLAT"));
            console.log("TestnetAsset (open faucet) deployed as underlying:", p.vault.asset);
        }
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCutsWithENS(p);
        vault = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();

        console.log("GovernedVaultENS diamond:", vault);
        console.log("  underlying asset:      ", p.vault.asset);
        console.log("  reverse registrar:     ", p.reverseRegistrar);
        console.log("  init (one-shot):       ", init);
        console.log("  claimed ENS name:      ", p.ensName);
        for (uint256 i; i < cuts.length; ++i) {
            console.log("  facet cut:", i, cuts[i].facetAddress);
        }
        console.log("NEXT STEPS:");
        console.log(" 1. The vault's REVERSE record (vault -> name) is already claimed. For the name to show as");
        console.log("    the vault's primary name, point the FORWARD record (name -> vault) at the diamond:");
        console.log("    set the name's addr record to the diamond via https://sepolia.app.ens.domains, or:");
        console.log("    cast send <PublicResolver> 'setAddr(bytes32,address)' <namehash(name)> <diamond>");
        console.log("    (Sepolia PublicResolver: 0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5)");
        console.log(" 2. Dogfood: mint TestnetAsset, approve the vault, deposit, delegate, propose.");
        console.log(" 3. Rename later via governance: propose setEnsName(newName) targeting the diamond.");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        GOVERNANCE DEMO (SELF-CRANKING)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The demo proposal's base description. STABLE within one attempt (so mid-lifecycle cranks
    ///         find their in-progress proposal), but the id also carries an ATTEMPT dimension so a
    ///         terminally-failed proposal (Defeated/Canceled/Expired) can be re-proposed with a fresh id —
    ///         otherwise the deterministic id would collide forever and the crank would dead-end.
    string public constant DEMO_DESCRIPTION =
        "Lattice M1: freeze loupe+cut selectors and reassert ENS name via governance";

    /// @notice The dogfood stake crank 1 mints/deposits (100% of vote supply on a fresh vault).
    uint256 public constant DEMO_DEPOSIT = 1_000e18;

    /// @notice Retry cap: the number of attempt descriptions {_activeAttempt} scans before giving up.
    uint256 internal constant DEMO_MAX_ATTEMPTS = 100;

    /// @notice Thrown when every attempt up to {DEMO_MAX_ATTEMPTS} has terminally failed — the operator
    ///         must diagnose why proposals keep losing (quorum, delegation) rather than retry blindly.
    error DeployGovernedVaultENS__DemoAttemptsExhausted();

    /// @notice SELF-CRANKING post-deploy governance runbook (broadcasting entrypoint): re-run the same
    ///         command as time passes and each invocation performs whatever the proposal state allows next
    ///         — dogfood+propose, vote, queue, execute — logging what to wait for in between. The proposal
    ///         is ONE combined payload: freeze the six load-bearing selectors (4 loupe + `diamondCut` +
    ///         `emergencyRemoveCut`) and re-assert the vault's ENS reverse record via governance. If an
    ///         attempt loses (a missed voting window Defeats it), the next crank self-heals onto a fresh
    ///         attempt id — the runbook can never permanently brick on a collided proposal id.
    /// @dev The broadcast wrapper passes `msg.sender` (the keystore signer — the account actually sending
    ///      every sub-call under `--broadcast`) as the actor to the broadcast-free step. The DOGFOOD path
    ///      is TESTNET-ONLY: it requires the vault underlying to be the open-faucet {TestnetAsset}
    ///      (balance-delta-probed; anything else reverts {DeployGovernedVaultENS__AssetNotOpenFaucet}
    ///      before a single real token moves). Real-asset vault operators fund + delegate manually — a
    ///      share balance > 0 skips dogfooding entirely, so they can still crank every proposal phase.
    function governanceDemo(address vault, string calldata ensName) external {
        vm.startBroadcast();
        governanceDemoStep(vault, ensName, msg.sender);
        vm.stopBroadcast();
    }

    /// @notice READ-ONLY status readout (no broadcast, no signing) — the machine-readable line an external
    ///         loop parses to decide whether to crank or sleep. Prints ONE line:
    ///         `DEMO-STATUS <state> <waitSeconds> <done> <attempt>` where `state` is the {IGovernor}
    ///         ProposalState uint8 (or the sentinel 8 = "nonexistent, needs propose"), `waitSeconds` is 0
    ///         when the next action is available NOW (else the seconds until it is), `done` is 1 only on
    ///         Executed, and `attempt` is the active retry index. Resolves the SAME active attempt as
    ///         {governanceDemoStep}, so status and step never disagree.
    /// @param actor The address whose ballot is checked (explicit: a dry-run read has no `msg.sender`; the
    ///        loop passes the broadcaster address).
    function governanceDemoStatus(address vault, string calldata ensName, address actor) external view {
        (uint8 state, uint256 waitSeconds, uint256 done, uint256 attempt) = _demoStatus(vault, ensName, actor);
        console.log(
            string.concat(
                "DEMO-STATUS ",
                vm.toString(state),
                " ",
                vm.toString(waitSeconds),
                " ",
                vm.toString(done),
                " ",
                vm.toString(attempt)
            )
        );
    }

    /// @notice One broadcast-free crank of the demo lifecycle — tests drive this directly with `vm.warp`
    ///         between cranks.
    /// @param vault The self-governed vault diamond.
    /// @param ensName The ENS name the proposal re-asserts (the vault's primary name).
    /// @param actor WHO sends the sub-calls in the current environment: the keystore signer under
    ///        `--broadcast` (the wrapper passes `msg.sender`), the SCRIPT CONTRACT INSTANCE when a test
    ///        calls this directly (no broadcast, so calls originate from this contract). Balance,
    ///        delegation, and ballot checks are all made against this address — pass the wrong one and the
    ///        crank dogfoods or votes on behalf of an address that is not sending the transactions.
    function governanceDemoStep(address vault, string memory ensName, address actor) public {
        uint256 attempt = _activeAttempt(vault, ensName);
        string memory description = _demoDescription(attempt);
        bytes32 descriptionHash = keccak256(bytes(description));
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            demoProposalPayload(vault, ensName);
        uint256 pid = IGovernor(vault).hashProposal(targets, values, calldatas, descriptionHash);

        // state() reverts GovernorNonexistentProposal before the active attempt exists — that IS the
        // propose case. Any surviving `current` is a LIVE state: _activeAttempt already advanced past every
        // terminally-failed attempt, so Defeated/Canceled/Expired cannot be the active attempt here.
        try IGovernor(vault).state(pid) returns (IGovernor.ProposalState current) {
            if (current == IGovernor.ProposalState.Pending) {
                console.log(
                    "[demo] attempt", attempt, "Pending: voting opens at", IGovernor(vault).proposalSnapshot(pid)
                );
                console.log("[demo]   seconds remaining:", IGovernor(vault).proposalSnapshot(pid) - block.timestamp);
            } else if (current == IGovernor.ProposalState.Active) {
                if (!IGovernor(vault).hasVoted(pid, actor)) {
                    IGovernor(vault).castVote(pid, uint8(IGovernor.VoteType.For));
                    console.log("[demo] Active: cast the For vote; re-run after the deadline");
                } else {
                    console.log("[demo] Active: already voted; vote closes at", IGovernor(vault).proposalDeadline(pid));
                }
            } else if (current == IGovernor.ProposalState.Succeeded) {
                IGovernor(vault).queue(targets, values, calldatas, descriptionHash);
                console.log("[demo] Succeeded: queued; executable at eta", IGovernor(vault).proposalEta(pid));
            } else if (current == IGovernor.ProposalState.Queued) {
                uint256 eta = IGovernor(vault).proposalEta(pid);
                if (eta <= block.timestamp) {
                    IGovernor(vault).execute(targets, values, calldatas, descriptionHash);
                    console.log("[demo] Queued->Executed: freeze + rename applied");
                    _logFrozen(vault);
                } else {
                    console.log("[demo] Queued: timelock delay remaining (seconds):", eta - block.timestamp);
                }
            } else if (current == IGovernor.ProposalState.Executed) {
                console.log("[demo] Executed: nothing left to crank. Verification reads:");
                _logFrozen(vault);
                console.log("[demo] The reverse record was re-asserted by the proposal (setEnsName).");
            } else {
                // Defensive: a live state changing under us is impossible in one call, but never crank blind.
                console.log("[demo] unexpected terminal state for the active attempt:", uint8(current));
            }
        } catch {
            _dogfood(vault, actor);
            uint256 proposed = IGovernor(vault).propose(targets, values, calldatas, description);
            console.log("[demo] proposed attempt", attempt);
            console.log("[demo]   id:", proposed);
            console.log("[demo] wait votingDelay, then re-run to vote");
        }
    }

    /// @notice The demo proposal's deterministic payload — the SAME bytes for EVERY attempt (only the
    ///         description varies), so tests/tooling can reconstruct the id for any attempt.
    function demoProposalPayload(address vault, string memory ensName)
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](2);
        targets[0] = vault;
        targets[1] = vault;
        values = new uint256[](2);

        bytes4[] memory frozen = new bytes4[](6);
        frozen[0] = IDiamondLoupe.facets.selector;
        frozen[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        frozen[2] = IDiamondLoupe.facetAddresses.selector;
        frozen[3] = IDiamondLoupe.facetAddress.selector;
        frozen[4] = IGovernedDiamondCut.diamondCut.selector;
        frozen[5] = IEmergencyCut.emergencyRemoveCut.selector;

        calldatas = new bytes[](2);
        calldatas[0] = abi.encodeCall(IFrozenSelectors.freezeSelectors, (frozen));
        calldatas[1] = abi.encodeCall(IENSReverseClaimer.setEnsName, (ensName));
    }

    /// @notice The proposal id of the ACTIVE attempt on `vault` (the one a crank works on next).
    function demoProposalId(address vault, string memory ensName) public view returns (uint256 pid) {
        pid = demoProposalId(vault, ensName, _activeAttempt(vault, ensName));
    }

    /// @notice The proposal id of a SPECIFIC attempt — same payload, attempt-varied description.
    function demoProposalId(address vault, string memory ensName, uint256 attempt) public pure returns (uint256 pid) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            demoProposalPayload(vault, ensName);
        pid = IGovernor(vault).hashProposal(targets, values, calldatas, keccak256(bytes(_demoDescription(attempt))));
    }

    /// @notice The description for a given retry `attempt`. Attempt 0 is the base description VERBATIM (so
    ///         it matches any pre-existing proposal made before retries were introduced); attempt N>=1
    ///         appends ` (retry N)`, minting a fresh proposal id past a terminal failure.
    function _demoDescription(uint256 attempt) internal pure returns (string memory) {
        if (attempt == 0) return DEMO_DESCRIPTION;
        return string.concat(DEMO_DESCRIPTION, " (retry ", vm.toString(attempt), ")");
    }

    /// @notice The active attempt index: the lowest attempt whose proposal is NOT terminally failed. Scans
    ///         attempts 0,1,2,...: a nonexistent proposal (never proposed) is the one to propose next; a
    ///         Defeated/Canceled/Expired proposal is skipped (retry with a fresh id); any live state
    ///         (Pending/Active/Succeeded/Queued) or terminal-SUCCESS (Executed) is the one to work on or
    ///         report. Reverts {DeployGovernedVaultENS__DemoAttemptsExhausted} past {DEMO_MAX_ATTEMPTS}.
    function _activeAttempt(address vault, string memory ensName) internal view returns (uint256) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            demoProposalPayload(vault, ensName);
        for (uint256 n; n < DEMO_MAX_ATTEMPTS; ++n) {
            uint256 pid =
                IGovernor(vault).hashProposal(targets, values, calldatas, keccak256(bytes(_demoDescription(n))));
            try IGovernor(vault).state(pid) returns (IGovernor.ProposalState s) {
                if (
                    s == IGovernor.ProposalState.Defeated || s == IGovernor.ProposalState.Canceled
                        || s == IGovernor.ProposalState.Expired
                ) {
                    continue; // terminally failed — advance to a fresh attempt id
                }
                return n; // live (or Executed) — work on / report this attempt
            } catch {
                return n; // nonexistent — this is the attempt to propose
            }
        }
        revert DeployGovernedVaultENS__DemoAttemptsExhausted();
    }

    /// @notice The active attempt's (state, waitSeconds, done, attempt) — the computation
    ///         {governanceDemoStatus} prints, exposed so tests read the values directly instead of parsing
    ///         console output. `state` is the ProposalState uint8, or 8 (sentinel) when the active attempt
    ///         does not exist yet; `waitSeconds` is 0 when actionable now; `done` is 1 only on Executed.
    function _demoStatus(address vault, string memory ensName, address actor)
        internal
        view
        returns (uint8 state, uint256 waitSeconds, uint256 done, uint256 attempt)
    {
        attempt = _activeAttempt(vault, ensName);
        uint256 pid = demoProposalId(vault, ensName, attempt);
        try IGovernor(vault).state(pid) returns (IGovernor.ProposalState s) {
            state = uint8(s);
            if (s == IGovernor.ProposalState.Pending) {
                uint256 snapshot = IGovernor(vault).proposalSnapshot(pid);
                waitSeconds = snapshot > block.timestamp ? snapshot - block.timestamp : 0;
            } else if (s == IGovernor.ProposalState.Active) {
                if (IGovernor(vault).hasVoted(pid, actor)) {
                    uint256 deadline = IGovernor(vault).proposalDeadline(pid);
                    waitSeconds = deadline > block.timestamp ? deadline - block.timestamp : 0;
                }
                // else: actionable now (vote) — waitSeconds stays 0
            } else if (s == IGovernor.ProposalState.Queued) {
                uint256 eta = IGovernor(vault).proposalEta(pid);
                waitSeconds = eta > block.timestamp ? eta - block.timestamp : 0;
            } else if (s == IGovernor.ProposalState.Executed) {
                done = 1;
            }
            // Succeeded: actionable now (queue) — waitSeconds 0, done 0
        } catch {
            state = 8; // sentinel: nonexistent, needs propose
        }
    }

    /// @dev Idempotent dogfood: stake + checkpoint only what `actor` is still missing. TESTNET-ONLY: the
    ///      faucet mint is balance-delta-probed — a WETH9-pattern underlying (no `mint(address,uint256)`,
    ///      non-reverting fallback) makes the phantom mint "succeed" while crediting nothing, and without
    ///      the probe the follow-up approve+deposit would pull the operator's REAL tokens.
    function _dogfood(address vault, address actor) private {
        if (IERC20(vault).balanceOf(actor) == 0) {
            address asset = IERC4626(vault).asset();
            uint256 balanceBefore = IERC20(asset).balanceOf(actor);
            TestnetAsset(asset).mint(actor, DEMO_DEPOSIT);
            if (IERC20(asset).balanceOf(actor) != balanceBefore + DEMO_DEPOSIT) {
                revert DeployGovernedVaultENS__AssetNotOpenFaucet(asset);
            }
            IERC20(asset).approve(vault, DEMO_DEPOSIT);
            IERC4626(vault).deposit(DEMO_DEPOSIT, actor);
            console.log("[demo] dogfooded: minted + deposited", DEMO_DEPOSIT);
        }
        if (IVotes(vault).delegates(actor) == address(0)) {
            IVotes(vault).delegate(actor);
            console.log("[demo] self-delegated voting power");
        }
    }

    /// @dev Logs the six load-bearing frozen-selector reads (the proposal's verifiable outcome).
    function _logFrozen(address vault) private view {
        bytes4[6] memory six = [
            IDiamondLoupe.facets.selector,
            IDiamondLoupe.facetFunctionSelectors.selector,
            IDiamondLoupe.facetAddresses.selector,
            IDiamondLoupe.facetAddress.selector,
            IGovernedDiamondCut.diamondCut.selector,
            IEmergencyCut.emergencyRemoveCut.selector
        ];
        for (uint256 i; i < 6; ++i) {
            console.log("[demo] isSelectorFrozen:", uint32(six[i]), IFrozenSelectors(vault).isSelectorFrozen(six[i]));
        }
    }
}
