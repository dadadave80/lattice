// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {CannotAddFunctionToDiamondThatAlreadyExists, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {ITimelockController} from "@lattice/interfaces/governance/ITimelockController.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                 FIXTURES
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal mintable ERC-20 used as the vault asset. Only the handler mints it.
contract GovAsset {
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice External proposal target. Records who executed each ping and when, so the suite can check that only the
///         timelock (the diamond) ran it, at most once, and never before its ETA.
contract GovSink {
    mapping(uint256 tag => uint256) public hits;
    mapping(uint256 tag => uint256) public hitAt;
    mapping(uint256 tag => address) public hitBy;
    uint256 public total;

    function ping(uint256 tag) external {
        ++hits[tag];
        hitAt[tag] = block.timestamp;
        hitBy[tag] = msg.sender;
        ++total;
    }
}

/// @notice Facet a governed cut installs or replaces. `govProbe()` returns the tag of the facet it routes to, so the
///         suite can tell which proposal's cut is live.
contract GovProbeFacet {
    uint256 public immutable tag;

    constructor(uint256 tag_) {
        tag = tag_;
    }

    function govProbe() external view returns (uint256) {
        return tag;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @title GovernorHandler
/// @notice Drives a recipe-built {DeployGovernedVault} diamond (Governor + its own TimelockController + Votes on the
///         vault shares + GovernedDiamondCut) through share entries, exits and transfers, delegation, proposals
///         (an external ping or a governed cut of a probe facet), votes, queueing, execution through the Governor or
///         directly through the open-executor timelock, cancellation, refused direct scheduling, and time.
/// @dev Revert-free under `fail_on_revert`: each call is either valid or arms the exact revert a ghost model of the
///      Governor predicts. The proposal state the model predicts is computed from ghost data only (snapshot,
///      deadline, tallies, queue/cancel/execute flags and a ghost supply history), never from the Governor.
contract GovernorHandler is Test {
    struct Prop {
        uint256 id;
        bytes32 tlId;
        address proposer;
        address target;
        bytes data;
        bytes32 descHash;
        uint8 kind; // 0 = ping the sink, 1 = governed cut of a probe facet
        uint256 tag;
        address probe;
        bool isAdd;
        uint48 snapshot;
        uint48 deadline;
        uint48 eta;
        bool queued;
        bool canceled;
        bool govExecuted;
        bool done;
        uint256 againstVotes;
        uint256 forVotes;
        uint256 abstainVotes;
        uint8 lastState;
    }

    struct Checkpoint {
        uint48 at;
        uint256 value;
    }

    uint8 internal constant PENDING = 0;
    uint8 internal constant ACTIVE = 1;
    uint8 internal constant CANCELED = 2;
    uint8 internal constant DEFEATED = 3;
    uint8 internal constant SUCCEEDED = 4;
    uint8 internal constant QUEUED = 5;
    uint8 internal constant EXPIRED = 6;
    uint8 internal constant EXECUTED = 7;

    uint256 internal constant MAX_PROPOSALS = 16;
    uint256 internal constant MAX_AMOUNT = 1e24;
    uint256 internal constant GRACE = 14 days;

    address public immutable gov;
    GovAsset public immutable asset;
    GovSink public immutable sink;
    uint48 public immutable votingDelay;
    uint32 public immutable votingPeriod;
    uint256 public immutable minDelay;
    uint256 public immutable quorumNumerator;

    address[4] internal _actors;
    /// @dev An address outside the actor set, used for refused calls.
    address internal constant OUTSIDER = address(0xBAD);

    Prop[] internal _props;
    mapping(address account => address) public ghostDelegate;
    mapping(address account => Checkpoint[]) internal _votesHistory;
    Checkpoint[] internal _supplyHistory;
    uint256 public ghostSharesMinted;
    uint256 public ghostSharesBurned;
    uint256 public ghostPings;
    uint256 public ghostCuts;
    bool public ghostProbeInstalled;
    address public ghostProbeFacet;
    uint256 public ghostProbeTag;
    mapping(uint256 proposal => mapping(address voter => bool)) public ghostHasVoted;

    /// @dev reach[a][b]: state b can follow state a (reflexive, transitive closure of the lifecycle edges).
    bool[8][8] internal _reach;

    constructor(
        address gov_,
        GovAsset asset_,
        GovSink sink_,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 minDelay_,
        uint256 quorumNumerator_
    ) {
        gov = gov_;
        asset = asset_;
        sink = sink_;
        votingDelay = votingDelay_;
        votingPeriod = votingPeriod_;
        minDelay = minDelay_;
        quorumNumerator = quorumNumerator_;
        _actors[0] = address(0xA11CE);
        _actors[1] = address(0xB0B);
        _actors[2] = address(0xCA201);
        _actors[3] = address(0xD0D);
        _buildReach();
    }

    // ---- Lifecycle edge table ----

    function _buildReach() internal {
        bool[8][8] memory e;
        e[PENDING][ACTIVE] = true;
        e[PENDING][CANCELED] = true;
        e[ACTIVE][CANCELED] = true;
        e[ACTIVE][DEFEATED] = true;
        e[ACTIVE][SUCCEEDED] = true;
        e[SUCCEEDED][CANCELED] = true;
        e[SUCCEEDED][QUEUED] = true;
        e[QUEUED][CANCELED] = true;
        e[QUEUED][EXPIRED] = true;
        e[QUEUED][EXECUTED] = true;
        // FINDING (G-1, known divergence, not intended behaviour): the 14-day grace exists only in
        // GovernorLib.state(). The timelock keeps the operation Ready and GovernedVaultInit opens its executor role,
        // so anyone can still run an Expired proposal with `executeBatch`, after which it reads Executed; and
        // GovernorLib.cancel refuses Expired, so the proposer cannot stop it. In OpenZeppelin's Governor, Expired is
        // terminal. The edge is modelled because the campaign reaches it, and
        // test_Finding_ExpiredProposalExecutableByAnyone pins it.
        e[EXPIRED][EXECUTED] = true;
        for (uint8 i; i < 8; ++i) {
            e[i][i] = true;
        }
        for (uint8 k; k < 8; ++k) {
            for (uint8 i; i < 8; ++i) {
                for (uint8 j; j < 8; ++j) {
                    if (e[i][k] && e[k][j]) e[i][j] = true;
                }
            }
        }
        for (uint8 i; i < 8; ++i) {
            for (uint8 j; j < 8; ++j) {
                _reach[i][j] = e[i][j];
            }
        }
    }

    // ---- Views for the invariants ----

    function actors() external view returns (address[4] memory) {
        return _actors;
    }

    function propCount() external view returns (uint256) {
        return _props.length;
    }

    function prop(uint256 i) external view returns (Prop memory) {
        return _props[i];
    }

    /// @notice The supply the ghost history holds at the end of timepoint `t`.
    function ghostSupplyAt(uint256 t) public view returns (uint256) {
        return _lookup(_supplyHistory, t);
    }

    /// @notice The votes the ghost history gives `account` at the end of timepoint `t`.
    function ghostVotesAt(address account, uint256 t) public view returns (uint256) {
        return _lookup(_votesHistory[account], t);
    }

    /// @notice The votes `account` should hold now: the shares of every actor delegating to it.
    function ghostVotesNow(address account) public view returns (uint256 v) {
        for (uint256 i; i < _actors.length; ++i) {
            if (ghostDelegate[_actors[i]] == account) v += IERC20(gov).balanceOf(_actors[i]);
        }
    }

    /// @notice The state the ghost model predicts for proposal `i`.
    function modelState(uint256 i) public view returns (uint8) {
        Prop storage p = _props[i];
        if (p.govExecuted) return EXECUTED;
        if (p.canceled) return CANCELED;
        if (p.snapshot >= block.timestamp) return PENDING;
        if (p.deadline >= block.timestamp) return ACTIVE;
        uint256 quorum = ghostSupplyAt(p.snapshot) * quorumNumerator / 100;
        if (p.forVotes <= p.againstVotes || p.forVotes + p.abstainVotes < quorum) return DEFEATED;
        if (!p.queued) return SUCCEEDED;
        if (p.done) return EXECUTED;
        if (block.timestamp > uint256(p.eta) + GRACE) return EXPIRED;
        return QUEUED;
    }

    function _lookup(Checkpoint[] storage h, uint256 t) internal view returns (uint256) {
        for (uint256 i = h.length; i > 0; --i) {
            if (h[i - 1].at <= t) return h[i - 1].value;
        }
        return 0;
    }

    function _write(Checkpoint[] storage h, uint256 value) internal {
        uint48 nowTs = uint48(block.timestamp);
        uint256 n = h.length;
        if (n != 0 && h[n - 1].at == nowTs) {
            h[n - 1].value = value;
        } else if (n == 0 || h[n - 1].value != value) {
            h.push(Checkpoint(nowTs, value));
        }
    }

    // ---- Post-action bookkeeping ----

    /// @dev Records the current votes and supply in the ghost histories, then checks that every proposal only moved
    ///      along the lifecycle edges since the last action.
    function _settle() internal {
        _write(_supplyHistory, IERC20(gov).totalSupply());
        for (uint256 i; i < _actors.length; ++i) {
            _write(_votesHistory[_actors[i]], ghostVotesNow(_actors[i]));
        }
        for (uint256 i; i < _props.length; ++i) {
            uint8 s = uint8(IGovernor(gov).state(_props[i].id));
            assertTrue(_reach[_props[i].lastState][s], "proposal state moved backwards or skipped an edge");
            _props[i].lastState = s;
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return _actors[seed % _actors.length];
    }

    /// @dev A proposal picked by `seed`. Seven seeds in eight prefer one the model puts in state `want`, so the late
    ///      lifecycle paths run often; the rest pick any proposal, which exercises the refusals.
    function _pick(uint256 seed, uint8 want) internal view returns (uint256) {
        uint256 n = _props.length;
        if (seed % 8 != 0) {
            for (uint256 k; k < n; ++k) {
                uint256 i = (seed / 8 + k) % n;
                if (modelState(i) == want) return i;
            }
        }
        return seed % n;
    }

    function _bitmap(uint8 s) internal pure returns (bytes32) {
        return bytes32(uint256(1) << s);
    }

    function _arrays(Prop storage p)
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        targets[0] = p.target;
        values = new uint256[](1);
        calldatas = new bytes[](1);
        calldatas[0] = p.data;
    }

    /// @dev Whether running proposal `p`'s call now would fail: an Add cut of a probe that is already installed.
    function _callFails(Prop storage p) internal view returns (bool) {
        return p.kind == 1 && p.isAdd && ghostProbeInstalled;
    }

    function _armCallFailure() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                CannotAddFunctionToDiamondThatAlreadyExists.selector, GovProbeFacet.govProbe.selector
            )
        );
    }

    /// @dev Applies the ghost effects of a successful execution of `p`, by either path.
    function _applyExecution(Prop storage p) internal {
        p.done = true;
        if (p.kind == 0) {
            ++ghostPings;
        } else {
            ++ghostCuts;
            ghostProbeInstalled = true;
            ghostProbeFacet = p.probe;
            ghostProbeTag = p.tag;
        }
    }

    // ---- Shares and delegation ----

    /// @notice Setup only: every actor deposits and self-delegates, so early proposals can reach quorum.
    function seed() external {
        for (uint256 i; i < _actors.length; ++i) {
            address a = _actors[i];
            uint256 assets = (i + 1) * 1e21;
            asset.mint(a, assets);
            vm.startPrank(a);
            asset.approve(gov, assets);
            ghostSharesMinted += IERC4626(gov).deposit(assets, a);
            IVotes(gov).delegate(a);
            vm.stopPrank();
            ghostDelegate[a] = a;
        }
        _settle();
    }

    function deposit(uint256 actorSeed, uint256 assets) external {
        address a = _actor(actorSeed);
        assets = bound(assets, 1, MAX_AMOUNT);
        asset.mint(a, assets);
        vm.startPrank(a);
        asset.approve(gov, assets);
        uint256 shares = IERC4626(gov).deposit(assets, a);
        vm.stopPrank();
        ghostSharesMinted += shares;
        _settle();
    }

    function redeem(uint256 actorSeed, uint256 shares) external {
        address a = _actor(actorSeed);
        uint256 bal = IERC20(gov).balanceOf(a);
        if (bal == 0) return;
        shares = bound(shares, 1, bal);
        vm.prank(a);
        IERC4626(gov).redeem(shares, a, a);
        ghostSharesBurned += shares;
        _settle();
    }

    function transferShares(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, IERC20(gov).balanceOf(from));
        vm.prank(from);
        IERC20(gov).transfer(to, amount);
        _settle();
    }

    /// @dev Delegates to another actor, or (one seed in five) to address(0), which drops the delegator's votes.
    function delegate(uint256 actorSeed, uint256 toSeed) external {
        address a = _actor(actorSeed);
        address to = toSeed % 5 == 4 ? address(0) : _actor(toSeed);
        vm.prank(a);
        IVotes(gov).delegate(to);
        ghostDelegate[a] = to;
        _settle();
    }

    // ---- Proposals ----

    /// @dev Skipped while two proposals are already Pending or Active, so ballots concentrate and proposals pass.
    function propose(uint256 actorSeed, uint256 kindSeed) external {
        if (_props.length >= MAX_PROPOSALS) return;
        uint256 live;
        for (uint256 i; i < _props.length; ++i) {
            uint8 st = modelState(i);
            if (st == PENDING || st == ACTIVE) ++live;
        }
        if (live >= 2) return;
        address proposer = _actor(actorSeed);
        uint256 n = _props.length;
        Prop storage p = _props.push();
        p.proposer = proposer;
        p.tag = n + 1;
        if (kindSeed % 3 == 2) {
            p.kind = 1;
            p.probe = address(new GovProbeFacet(n + 1));
            p.isAdd = !ghostProbeInstalled;
            FacetCut[] memory cuts = new FacetCut[](1);
            bytes4[] memory sels = new bytes4[](1);
            sels[0] = GovProbeFacet.govProbe.selector;
            cuts[0] = FacetCut({
                facetAddress: p.probe,
                action: p.isAdd ? FacetCutAction.Add : FacetCutAction.Replace,
                functionSelectors: sels
            });
            p.target = gov;
            p.data = abi.encodeCall(IGovernedDiamondCut.diamondCut, (cuts, address(0), ""));
        } else {
            p.target = address(sink);
            p.data = abi.encodeCall(GovSink.ping, (n + 1));
        }
        string memory description = string.concat("governor-invariant-", vm.toString(n + 1));
        p.descHash = keccak256(bytes(description));
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _arrays(p);
        p.id = uint256(keccak256(abi.encode(targets, values, calldatas, p.descHash)));
        p.tlId = keccak256(abi.encode(targets, values, calldatas, bytes32(0), bytes32(p.id)));
        p.snapshot = uint48(block.timestamp) + votingDelay;
        p.deadline = p.snapshot + votingPeriod;

        vm.prank(proposer);
        uint256 id = IGovernor(gov).propose(targets, values, calldatas, description);
        assertEq(id, p.id, "proposal id != hashProposal");
        p.lastState = PENDING;
        _settle();
    }

    /// @dev Casts a ballot. Outside the Active window, a second ballot, and an unknown support value are refused.
    function castVote(uint256 actorSeed, uint256 propSeed, uint8 support) external {
        if (_props.length == 0) return;
        uint256 idx = _pick(propSeed, ACTIVE);
        Prop storage p = _props[idx];
        address voter = _actor(actorSeed);
        // Biased toward For so proposals pass: 0 Against, 1-4 and 6 For, 5 Abstain, 7 the invalid type 3.
        support = uint8(bound(support, 0, 7));
        support = support == 0 ? 0 : support == 5 ? 2 : support == 7 ? 3 : 1;
        uint8 s = modelState(idx);

        vm.prank(voter);
        if (s != ACTIVE) {
            vm.expectRevert(
                abi.encodeWithSelector(IGovernor.GovernorUnexpectedProposalState.selector, p.id, s, _bitmap(ACTIVE))
            );
            IGovernor(gov).castVote(p.id, support);
        } else if (ghostHasVoted[p.id][voter]) {
            vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorAlreadyCastVote.selector, voter));
            IGovernor(gov).castVote(p.id, support);
        } else if (support == 3) {
            vm.expectRevert(IGovernor.GovernorInvalidVoteType.selector);
            IGovernor(gov).castVote(p.id, support);
        } else {
            uint256 expected = ghostVotesAt(voter, p.snapshot);
            uint256 weight = IGovernor(gov).castVote(p.id, support);
            assertEq(weight, expected, "ballot weight != ghost votes at snapshot");
            ghostHasVoted[p.id][voter] = true;
            if (support == 0) p.againstVotes += weight;
            else if (support == 1) p.forVotes += weight;
            else p.abstainVotes += weight;
        }
        _settle();
    }

    function queue(uint256 propSeed) external {
        if (_props.length == 0) return;
        uint256 idx = _pick(propSeed, SUCCEEDED);
        Prop storage p = _props[idx];
        uint8 s = modelState(idx);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _arrays(p);

        if (p.queued) {
            vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorAlreadyQueuedProposal.selector, p.id));
        } else if (s != SUCCEEDED) {
            vm.expectRevert(
                abi.encodeWithSelector(IGovernor.GovernorUnexpectedProposalState.selector, p.id, s, _bitmap(SUCCEEDED))
            );
        }
        IGovernor(gov).queue(targets, values, calldatas, p.descHash);
        if (!p.queued && s == SUCCEEDED) {
            p.queued = true;
            p.eta = uint48(block.timestamp + minDelay);
            assertEq(IGovernor(gov).proposalEta(p.id), p.eta, "eta != queue time + minDelay");
        }
        _settle();
    }

    /// @dev Executes through the Governor. Only a Queued proposal whose timelock operation is Ready runs.
    function execute(uint256 propSeed) external {
        if (_props.length == 0) return;
        uint256 idx = _pick(propSeed, QUEUED);
        Prop storage p = _props[idx];
        uint8 s = modelState(idx);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _arrays(p);

        bool ok;
        if (s != QUEUED) {
            vm.expectRevert(
                abi.encodeWithSelector(IGovernor.GovernorUnexpectedProposalState.selector, p.id, s, _bitmap(QUEUED))
            );
        } else if (block.timestamp < p.eta) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITimelockController.TimelockUnexpectedOperationState.selector, p.tlId, _bitmap(2)
                )
            );
        } else if (_callFails(p)) {
            _armCallFailure();
        } else {
            ok = true;
        }
        IGovernor(gov).execute(targets, values, calldatas, p.descHash);
        if (ok) {
            p.govExecuted = true;
            _applyExecution(p);
        }
        _settle();
    }

    /// @dev Executes straight through the timelock's open executor role, bypassing the Governor. Only an operation
    ///      the Governor queued, past its ETA, and not yet done or cancelled, runs. That includes an Expired
    ///      proposal's operation, which is a known divergence from OpenZeppelin (see the FINDING note in
    ///      `_buildReach` and test_Finding_ExpiredProposalExecutableByAnyone), so one seed in three targets one.
    function executeDirect(uint256 actorSeed, uint256 propSeed) external {
        if (_props.length == 0) return;
        Prop storage p = _props[_pick(propSeed, propSeed % 3 == 0 ? EXPIRED : QUEUED)];
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _arrays(p);

        bool ready = p.queued && !p.canceled && !p.done && block.timestamp >= p.eta;
        bool ok;
        if (!ready) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ITimelockController.TimelockUnexpectedOperationState.selector, p.tlId, _bitmap(2)
                )
            );
        } else if (_callFails(p)) {
            _armCallFailure();
        } else {
            ok = true;
        }
        vm.prank(_actor(actorSeed));
        ITimelockController(gov).executeBatch(targets, values, calldatas, bytes32(0), bytes32(p.id));
        if (ok) _applyExecution(p);
        _settle();
    }

    /// @dev Cancels as the proposer (one seed in sixteen, so most proposals live on) or as another actor. Only the
    ///      proposer may cancel, and only while the proposal is Pending, Active, Succeeded or Queued.
    ///      FINDING (G-2, known divergence, not intended behaviour): OpenZeppelin lets the proposer cancel only while
    ///      Pending, but GovernorLib.cancel also accepts Succeeded and Queued, so one account can veto a proposal
    ///      that passed its vote. test_Finding_ProposerCancelsQueuedProposal pins it.
    function cancel(uint256 propSeed, uint256 callerSeed) external {
        if (_props.length == 0) return;
        uint256 idx = propSeed % _props.length;
        Prop storage p = _props[idx];
        uint8 s = modelState(idx);
        address caller = p.proposer;
        if (callerSeed % 16 != 0) {
            caller = _actor(callerSeed);
            if (caller == p.proposer) caller = _actors[(callerSeed % _actors.length + 1) % _actors.length];
        }
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _arrays(p);

        bool cancellable = s == PENDING || s == ACTIVE || s == SUCCEEDED || s == QUEUED;
        if (!cancellable) {
            bytes32 allowed = _bitmap(PENDING) | _bitmap(ACTIVE) | _bitmap(SUCCEEDED) | _bitmap(QUEUED);
            vm.expectRevert(
                abi.encodeWithSelector(IGovernor.GovernorUnexpectedProposalState.selector, p.id, s, allowed)
            );
        } else if (caller != p.proposer) {
            vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, caller));
        }
        vm.prank(caller);
        IGovernor(gov).cancel(targets, values, calldatas, p.descHash);
        if (cancellable && caller == p.proposer) p.canceled = true;
        _settle();
    }

    /// @dev Anyone but the Governor scheduling on the timelock is refused: only queued proposals reach it.
    function scheduleDirect(uint256 actorSeed, uint256 tag) external {
        address caller = actorSeed % 5 == 4 ? OUTSIDER : _actor(actorSeed);
        address[] memory targets = new address[](1);
        targets[0] = address(sink);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(GovSink.ping, (tag));
        bytes32 proposerRole = ITimelockController(gov).PROPOSER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, proposerRole)
        );
        vm.prank(caller);
        ITimelockController(gov).scheduleBatch(targets, values, calldatas, bytes32(0), bytes32(tag), minDelay);
    }

    /// @dev Anyone but the diamond itself cutting is refused: a cut only lands through an executed proposal.
    function cutDirect(uint256 actorSeed) external {
        address caller = actorSeed % 5 == 4 ? OUTSIDER : _actor(actorSeed);
        FacetCut[] memory cuts = new FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = GovProbeFacet.govProbe.selector;
        cuts[0] = FacetCut({facetAddress: address(sink), action: FacetCutAction.Add, functionSelectors: sels});
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, keccak256("UPGRADE_EXECUTOR_ROLE")
            )
        );
        vm.prank(caller);
        IGovernedDiamondCut(gov).diamondCut(cuts, address(0), "");
    }

    // ---- Time ----

    /// @dev Moves time by up to a third of a proposal's lifetime, or (one seed in 64) past the 14-day grace
    ///      so queued proposals can expire.
    function warp(uint256 secs) external {
        if (secs % 64 == 0) {
            secs = GRACE + 1;
        } else {
            secs = bound(secs, 1, (uint256(votingDelay) + votingPeriod + minDelay) / 3);
        }
        vm.warp(vm.getBlockTimestamp() + secs);
        _settle();
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                 INVARIANTS
//////////////////////////////////////////////////////////////////////////*//

/// @title GovernorDiamondInvariant
/// @notice Stateful properties of the Governor, its timelock and the Votes checkpoints on a recipe-built
///         {DeployGovernedVault} diamond (#231):
///         - voting power is conserved: each account's votes are the shares delegated to it, and past votes and past
///           supply at every proposal snapshot match a ghost history and never change afterwards;
///         - each tally is the sum of its ballots, each weighted by the voter's votes at the snapshot;
///         - a proposal's state matches a ghost model of the lifecycle and only moves forward along its edges;
///         - the timelock runs only operations the Governor queued, at most once, never before the ETA, and only as
///           the diamond; nobody else can schedule on it or cut the diamond.
/// forge-config: ci.invariant.runs = 64
contract GovernorDiamondInvariant is Test {
    GovernorHandler internal handler;
    address internal gov;
    GovSink internal sink;

    uint48 internal constant VOTING_DELAY = 10;
    uint32 internal constant VOTING_PERIOD = 500;
    uint256 internal constant MIN_DELAY = 120;
    uint256 internal constant QUORUM = 4;

    function setUp() public {
        vm.warp(1_000_000);
        GovAsset asset = new GovAsset();
        GovernedVaultParams memory p;
        p.asset = address(asset);
        p.name = "Governor Invariant Share";
        p.symbol = "gINV";
        p.minDelay = MIN_DELAY;
        p.votingDelay = VOTING_DELAY;
        p.votingPeriod = VOTING_PERIOD;
        p.quorumNumerator = QUORUM;
        LatticeFactory factory = new LatticeFactory(new LatticeRegistry(address(this)), address(0), address(0));
        gov = new DeployGovernedVault().deployAtomic(p, factory, bytes32(0));
        sink = new GovSink();

        handler = new GovernorHandler(gov, asset, sink, VOTING_DELAY, VOTING_PERIOD, MIN_DELAY, QUORUM);

        handler.seed();

        bytes4[] memory selectors = new bytes4[](17);
        selectors[0] = GovernorHandler.deposit.selector;
        selectors[1] = GovernorHandler.redeem.selector;
        selectors[2] = GovernorHandler.transferShares.selector;
        selectors[3] = GovernorHandler.delegate.selector;
        selectors[4] = GovernorHandler.propose.selector;
        selectors[5] = GovernorHandler.castVote.selector;
        // Ballots weighted three times so proposals reach quorum and the queue/execute paths run.
        selectors[6] = GovernorHandler.castVote.selector;
        selectors[7] = GovernorHandler.queue.selector;
        selectors[8] = GovernorHandler.execute.selector;
        selectors[9] = GovernorHandler.executeDirect.selector;
        selectors[10] = GovernorHandler.cancel.selector;
        // Time weighted twice so proposals move through their windows.
        selectors[11] = GovernorHandler.warp.selector;
        selectors[12] = GovernorHandler.scheduleDirect.selector;
        selectors[13] = GovernorHandler.cutDirect.selector;
        selectors[14] = GovernorHandler.warp.selector;
        selectors[15] = GovernorHandler.castVote.selector;
        // Proposals weighted twice (`propose` holds off while two are live) so a proposal is usually open.
        selectors[16] = GovernorHandler.propose.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice Each account's votes are exactly the shares of the actors delegating to it, `delegates` matches the
    ///         ghost, and the share supply is minted − burned = Σ holders ≥ Σ votes.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_VotingPowerConserved() public view {
        address[4] memory a = handler.actors();
        uint256 votes;
        uint256 balances;
        for (uint256 i; i < a.length; ++i) {
            assertEq(IVotes(gov).delegates(a[i]), handler.ghostDelegate(a[i]), "delegate diverged from ghost");
            uint256 v = IVotes(gov).getVotes(a[i]);
            assertEq(v, handler.ghostVotesNow(a[i]), "votes != shares delegated to the account");
            votes += v;
            balances += IERC20(gov).balanceOf(a[i]);
        }
        uint256 supply = IERC20(gov).totalSupply();
        assertEq(supply, handler.ghostSharesMinted() - handler.ghostSharesBurned(), "supply != minted - burned");
        assertEq(balances, supply, "supply != sum of holders");
        assertLe(votes, supply, "votes exceed supply");
    }

    /// @notice At every proposal snapshot already in the past, past votes, past supply and the quorum match the
    ///         ghost history, so later transfers and delegations never rewrite them.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_PastVotesFrozen() public view {
        address[4] memory a = handler.actors();
        uint256 n = handler.propCount();
        for (uint256 i; i < n; ++i) {
            uint256 snap = handler.prop(i).snapshot;
            if (snap >= block.timestamp) continue;
            uint256 supply = handler.ghostSupplyAt(snap);
            assertEq(IVotes(gov).getPastTotalSupply(snap), supply, "past supply != ghost");
            assertEq(IGovernor(gov).quorum(snap), supply * QUORUM / 100, "quorum != ghost supply share");
            for (uint256 j; j < a.length; ++j) {
                assertEq(IVotes(gov).getPastVotes(a[j], snap), handler.ghostVotesAt(a[j], snap), "past votes != ghost");
            }
        }
    }

    /// @notice Each proposal's tally is the sum of its ballots, `hasVoted` matches the ballots cast, and no tally
    ///         exceeds the supply at its snapshot.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_TallyIsSumOfBallots() public view {
        address[4] memory a = handler.actors();
        uint256 n = handler.propCount();
        for (uint256 i; i < n; ++i) {
            GovernorHandler.Prop memory p = handler.prop(i);
            (uint256 against, uint256 forV, uint256 abstain) = IGovernor(gov).proposalVotes(p.id);
            assertEq(against, p.againstVotes, "against tally != ballots");
            assertEq(forV, p.forVotes, "for tally != ballots");
            assertEq(abstain, p.abstainVotes, "abstain tally != ballots");
            if (p.snapshot < block.timestamp) {
                assertLe(against + forV + abstain, handler.ghostSupplyAt(p.snapshot), "tally exceeds snapshot supply");
            }
            for (uint256 j; j < a.length; ++j) {
                assertEq(IGovernor(gov).hasVoted(p.id, a[j]), handler.ghostHasVoted(p.id, a[j]), "hasVoted != ghost");
            }
        }
    }

    /// @notice Each proposal's state, snapshot, deadline, proposer and ETA match the ghost lifecycle model.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_StateMatchesModel() public view {
        uint256 n = handler.propCount();
        for (uint256 i; i < n; ++i) {
            GovernorHandler.Prop memory p = handler.prop(i);
            assertEq(uint8(IGovernor(gov).state(p.id)), handler.modelState(i), "state != ghost model");
            assertEq(IGovernor(gov).proposalSnapshot(p.id), p.snapshot, "snapshot != ghost");
            assertEq(IGovernor(gov).proposalDeadline(p.id), p.deadline, "deadline != ghost");
            assertEq(IGovernor(gov).proposalProposer(p.id), p.proposer, "proposer != ghost");
            assertEq(IGovernor(gov).proposalEta(p.id), p.eta, "eta != ghost");
        }
    }

    /// @notice The timelock holds an operation only for a queued, uncancelled proposal, marks it done exactly when
    ///         it ran, and every run happened once, as the diamond, at or after the ETA. Governed cuts are counted
    ///         in the upgrade registry and the probe routes to the last executed cut's facet.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_TimelockRunsOnlyQueued() public view {
        uint256 n = handler.propCount();
        uint256 pings;
        for (uint256 i; i < n; ++i) {
            GovernorHandler.Prop memory p = handler.prop(i);
            ITimelockController tl = ITimelockController(gov);
            assertEq(tl.isOperation(p.tlId), p.queued && (!p.canceled || p.done), "timelock op without a queue");
            assertEq(tl.isOperationDone(p.tlId), p.done, "timelock done != ghost");
            if (p.queued && !p.canceled && !p.done) {
                assertEq(tl.getTimestamp(p.tlId), p.eta, "timelock ready time != eta");
            }
            if (p.kind == 0) {
                assertEq(sink.hits(p.tag), p.done ? 1 : 0, "ping ran other than once per execution");
                if (p.done) {
                    assertGe(sink.hitAt(p.tag), p.eta, "ping ran before its eta");
                    assertEq(sink.hitBy(p.tag), gov, "ping not run by the timelock");
                    ++pings;
                }
            }
        }
        assertEq(sink.total(), pings, "sink ran an unqueued call");
        assertEq(sink.total(), handler.ghostPings(), "sink hits != ghost");
        assertEq(IUpgradeRegistry(gov).cutCount(), handler.ghostCuts(), "cutCount != executed governed cuts");
        address probeFacet = DiamondLoupeFacet(gov).facetAddress(GovProbeFacet.govProbe.selector);
        assertEq(probeFacet, handler.ghostProbeFacet(), "probe facet != last executed cut");
        if (handler.ghostProbeInstalled()) {
            assertEq(GovProbeFacet(gov).govProbe(), handler.ghostProbeTag(), "probe routes to a stale cut");
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    FINDINGS (known divergences, pinned)
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Proposes a ping of `tag`, has every seeded actor vote For, and queues it. Returns the proposal's call
    ///      arrays, id and timelock operation id.
    function _passAndQueue(uint256 tag)
        internal
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descHash,
            uint256 id,
            bytes32 tlId
        )
    {
        address[4] memory a = handler.actors();
        targets = new address[](1);
        targets[0] = address(sink);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(GovSink.ping, (tag));
        string memory description = string.concat("governor-finding-", vm.toString(tag));
        descHash = keccak256(bytes(description));

        vm.prank(a[0]);
        id = IGovernor(gov).propose(targets, values, calldatas, description);
        tlId = keccak256(abi.encode(targets, values, calldatas, bytes32(0), bytes32(id)));
        vm.warp(IGovernor(gov).proposalSnapshot(id) + 1);
        for (uint256 i; i < a.length; ++i) {
            vm.prank(a[i]);
            IGovernor(gov).castVote(id, 1);
        }
        vm.warp(IGovernor(gov).proposalDeadline(id) + 1);
        assertEq(uint8(IGovernor(gov).state(id)), uint8(IGovernor.ProposalState.Succeeded), "proposal did not pass");
        IGovernor(gov).queue(targets, values, calldatas, descHash);
        assertEq(uint8(IGovernor(gov).state(id)), uint8(IGovernor.ProposalState.Queued), "proposal not queued");
    }

    /// @notice FINDING (G-1, #322): an Expired proposal is not terminal. The 14-day grace exists only in
    ///         `GovernorLib.state()`, so the timelock operation stays Ready, and its executor role is open, so ANY
    ///         account still runs it with `executeBatch`; the proposal then reads Executed. Its proposer cannot stop
    ///         this, because `cancel` refuses Expired. In OpenZeppelin's Governor, Expired is terminal. A fix
    ///         either refuses execution after the grace or cancels the operation in the timelock.
    function test_Finding_ExpiredProposalExecutableByAnyone() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descHash,
            uint256 id,
            bytes32 tlId
        ) = _passAndQueue(1001);
        vm.warp(IGovernor(gov).proposalEta(id) + 14 days + 1);
        assertEq(uint8(IGovernor(gov).state(id)), uint8(IGovernor.ProposalState.Expired), "not expired");
        assertTrue(ITimelockController(gov).isOperationReady(tlId), "timelock op no longer ready");

        bytes32 cancellable = bytes32(uint256((1 << 0) | (1 << 1) | (1 << 4) | (1 << 5)));
        address proposer = IGovernor(gov).proposalProposer(id);
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector, id, IGovernor.ProposalState.Expired, cancellable
            )
        );
        vm.prank(proposer);
        IGovernor(gov).cancel(targets, values, calldatas, descHash);

        vm.prank(address(0xBAD));
        ITimelockController(gov).executeBatch(targets, values, calldatas, bytes32(0), bytes32(id));
        assertEq(sink.hits(1001), 1, "expired proposal did not run");
        assertEq(uint8(IGovernor(gov).state(id)), uint8(IGovernor.ProposalState.Executed), "not executed");
    }

    /// @notice FINDING (G-2, #323): the proposer alone can cancel a proposal after it passed its vote and was queued,
    ///         which also cancels its timelock operation. OpenZeppelin allows a proposer cancel only while Pending.
    function test_Finding_ProposerCancelsQueuedProposal() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bytes32 descHash,
            uint256 id,
            bytes32 tlId
        ) = _passAndQueue(1002);
        assertTrue(ITimelockController(gov).isOperation(tlId), "not scheduled");

        vm.prank(IGovernor(gov).proposalProposer(id));
        IGovernor(gov).cancel(targets, values, calldatas, descHash);
        assertEq(uint8(IGovernor(gov).state(id)), uint8(IGovernor.ProposalState.Canceled), "not canceled");
        assertFalse(ITimelockController(gov).isOperation(tlId), "timelock op survived the cancel");
    }
}
