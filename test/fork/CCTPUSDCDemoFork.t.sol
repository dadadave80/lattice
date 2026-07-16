// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {CCTPUSDCDemo} from "@lattice-script/base/crosschain/CCTPUSDCDemo.s.sol";
import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Exposes {CCTPUSDCDemo}'s broadcast-free internals so tests assert the parsed values directly
///         instead of scraping console output (the probe idiom of the governance-demo fork suites). Stateless
///         over the destinations/hub, so one probe serves every destination and phase.
contract CCTPUSDCDemoProbe is CCTPUSDCDemo {
    function dest(string calldata key) external pure returns (Dest memory) {
        return _dest(key);
    }

    function setupHub(address admin, uint256 maxFee, uint32 minFinality) external returns (address) {
        return _setupHub(admin, maxFee, minFinality);
    }

    function demoStatus(
        address diamond,
        address actor,
        uint256 amount,
        Dest memory d,
        uint256 burned,
        uint256 dstBaseline
    ) external returns (uint8 phase, uint256 waitSeconds, uint256 done, uint256 srcBal, uint256 dstBal) {
        return _demoStatus(diamond, actor, amount, d, burned, dstBaseline);
    }
}

/// @title CCTPUSDCDemoFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice ARC-HUB fork proof of the {CCTPUSDCDemo} self-cranking CCTP v2 USDC runbook: assembles the ONE
///         production {DeployCCTPBridgeAdapter} diamond on Circle's Arc testnet (the SOURCE), burns REAL Arc
///         USDC (the native gas token) through the LIVE Arc `TokenMessengerV2` toward BOTH destinations, and
///         asserts the machine-readable status tuple across every phase. Two destinations are exercised:
///         `sepolia` (Arc -> Ethereum Sepolia) and `base` (Arc -> Base Sepolia).
///
///         NEVER relay/mint INTO an Arc fork: on Arc every account is EIP-7702-delegated, and forge's revm
///         simulation reverts executing the delegated-account mint path. These tests only BURN on Arc (source
///         side) and SIMULATE a destination credit with a plain `deal()` on the destination's normal ERC-20 —
///         they never drive `receiveMessage` on Arc.
///
/// Enabling:
///   export ARC_TESTNET_RPC_URL=<...>        # required for the WHOLE suite (the burn source is Arc now)
///   export SEPOLIA_RPC_URL=<...>            # enables the *_Sepolia status test (forks the Sepolia dest)
///   export BASE_SEPOLIA_RPC_URL=<...>       # enables the *_Base    status test (forks the Base   dest)
///   forge test --match-path "test/fork/CCTPUSDCDemoFork.t.sol"
///
/// Without ARC_TESTNET_RPC_URL the whole suite skips. The setup + burn tests are Arc-only (they never fork a
/// destination). The per-destination status test additionally skips unless its destination RPC is set. Fork
/// blocks are pinned (overridable via <ALIAS>_FORK_BLOCK) so runs reproduce and the RPC cache hits;
/// {CCTPUSDCDemo._demoStatus} itself forks at the LIVE tip (status is inherently current), and the deployed
/// hub + dealt balances are carried across those forks with `vm.makePersistent`.
contract CCTPUSDCDemoFork is Test {
    /// @notice Circle CCTP v2 `TokenMessengerV2` on every testnet (asserted allowance target after a burn).
    address internal constant TOKEN_MESSENGER_V2 = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;
    /// @notice USDC on Arc testnet — the native gas token, a 6-decimal ERC-20 view (`balanceOf = balance/1e12`).
    address internal constant ARC_USDC = 0x3600000000000000000000000000000000000000;

    /// @notice Pinned fork blocks (overridable via env). The Arc source default is a recent testnet height
    ///         (chosen below the live tip so the cache hits); the destination defaults are recent testnet
    ///         heights whose USDC contract state is available — bump them (or set <ALIAS>_FORK_BLOCK) if an RPC
    ///         prunes state before them. `_demoStatus` forks at the live tip regardless.
    uint256 internal constant DEFAULT_ARC_TESTNET_FORK_BLOCK = 52_000_000;
    uint256 internal constant DEFAULT_SEPOLIA_FORK_BLOCK = 11_239_288;
    uint256 internal constant DEFAULT_BASE_SEPOLIA_FORK_BLOCK = 44_000_000;

    uint256 internal constant AMOUNT = 1_000_000; // 1 USDC (6 decimals)

    CCTPUSDCDemoProbe internal probe;
    address internal actor; // the probe instance — the sender of every broadcast-free sub-call

    function setUp() public {
        if (bytes(vm.envOr("ARC_TESTNET_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        _forkArc();
        probe = new CCTPUSDCDemoProbe();
        actor = address(probe);
        // Tests, unlike scripts, do NOT auto-persist helpers across forks — the probe must survive re-forking.
        vm.makePersistent(address(probe));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    function _forkArc() internal {
        vm.createSelectFork("arc-testnet", vm.envOr("ARC_TESTNET_FORK_BLOCK", DEFAULT_ARC_TESTNET_FORK_BLOCK));
    }

    function _forkDest(CCTPUSDCDemo.Dest memory d) internal {
        if (keccak256(bytes(d.key)) == keccak256("base")) {
            vm.createSelectFork(d.rpcAlias, vm.envOr("BASE_SEPOLIA_FORK_BLOCK", DEFAULT_BASE_SEPOLIA_FORK_BLOCK));
        } else {
            vm.createSelectFork(d.rpcAlias, vm.envOr("SEPOLIA_FORK_BLOCK", DEFAULT_SEPOLIA_FORK_BLOCK));
        }
    }

    /// @dev True (and does not skip) when `envKey` is set; otherwise marks the test skipped and returns false.
    function _dstRpcReady(string memory envKey) internal returns (bool) {
        if (bytes(vm.envOr(envKey, string(""))).length == 0) {
            vm.skip(true);
            return false;
        }
        return true;
    }

    /// @dev The destination RPC env var for a destination preset.
    function _dstRpcVar(CCTPUSDCDemo.Dest memory d) internal pure returns (string memory) {
        return keccak256(bytes(d.key)) == keccak256("base") ? "BASE_SEPOLIA_RPC_URL" : "SEPOLIA_RPC_URL";
    }

    /// @dev Carries a freshly-deployed diamond (proxy + every loupe-reported facet) across future forks.
    function _persist(address diamond) internal {
        vm.makePersistent(diamond);
        address[] memory facets = IDiamondLoupe(diamond).facetAddresses();
        for (uint256 i; i < facets.length; ++i) {
            vm.makePersistent(facets[i]);
        }
    }

    /// @dev Wiring assertions for one destination domain on the Arc hub (hub active on the current fork).
    function _assertDestWired(address hub, CCTPUSDCDemo.Dest memory d) internal view {
        assertTrue(ICCTPBridgeAdapter(hub).isChainRegistered(d.chainId), "destination chain registered");
        assertEq(ICCTPBridgeAdapter(hub).getDomain(d.chainId), d.domain, "destination domain mapped");
        (uint256 maxFee, uint32 minFinality, bytes32 destCaller) = ICCTPBridgeAdapter(hub).getDomainConfig(d.domain);
        assertEq(maxFee, 0, "standard free burn: maxFee 0");
        assertEq(minFinality, 2000, "standard finality threshold");
        assertEq(destCaller, bytes32(0), "permissionless mint");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     SETUP — ONE Arc hub wiring BOTH destinations
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Assembles the ONE hub on the Arc fork and asserts it is wired to the Arc native USDC and has
    ///         BOTH destination domains (Sepolia 0 and Base Sepolia 6) registered + configured free/standard.
    ///         Arc-only: reads the hub's own registrations, never forks a destination.
    function test_Fork_SetupAssemblesHubOnArcWithBothDomains() public {
        address hub = probe.setupHub(actor, 0, 2000);

        assertEq(ICCTPBridgeAdapter(hub).usdc(), ARC_USDC, "usdc() wired to Arc native USDC");
        assertEq(ICCTPBridgeAdapter(hub).tokenMessenger(), TOKEN_MESSENGER_V2, "tokenMessenger() wired");

        _assertDestWired(hub, probe.dest("sepolia"));
        _assertDestWired(hub, probe.dest("base"));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     BURN — Arc USDC move under revm (native precompile)
    //////////////////////////////////////////////////////////////////////////*//
    //
    // EMPIRICAL BLOCKER (established live this session — see the PR/commit body). On Arc, USDC IS the native gas
    // token: `balanceOf` reads `account.balance / 1e12`, but EVERY balance-MOVING op (`transfer` / `transferFrom`
    // and, symmetrically, the destination `mint`) routes through a NODE-LEVEL precompile at
    // 0x1800000000000000000000000000000000000000 (a 1-byte code stub). revm does not implement that precompile,
    // so any such call reverts under a fork with `[StackUnderflow]` then `[Revert]` — the burn's `pullExact`
    // `transferFrom` surfaces it as {IBridgeFungible.BridgeTransferFailed}. This is the SAME root cause the task
    // flagged for mint-INTO-Arc; it applies equally to burn-FROM-Arc. Consequences these tests pin:
    //   * A funded Arc burn CANNOT be simulated by revm (asserted below), so `forge script cctpDemoBurn` cannot
    //     execute the burn body during its collect phase — the Arc burn must be sent out-of-band (e.g. `cast
    //     send`, which the Arc NODE executes correctly). Only `balanceOf` (setUp/status) and `approve`
    //     (storage-only) simulate on an Arc fork.
    //   * The pre-transfer balance guard still fires (it reads `balanceOf`, which works), so a short balance is
    //     rejected BEFORE the unsimulatable transfer — proven by the guard test.

    /// @notice A FUNDED Arc burn toward Sepolia reverts under revm at the source-side `transferFrom` (Arc's
    ///         native-token precompile 0x1800 is absent from revm); the actor's funds are untouched.
    function test_Fork_ArcUSDCBurnRevertsUnderRevm_Sepolia() public {
        _arcBurnRevertsUnderRevm("sepolia");
    }

    /// @notice A FUNDED Arc burn toward Base Sepolia reverts under revm at the source-side `transferFrom` (same
    ///         0x1800 native-precompile blocker; the target domain does not change the outcome).
    function test_Fork_ArcUSDCBurnRevertsUnderRevm_Base() public {
        _arcBurnRevertsUnderRevm("base");
    }

    function _arcBurnRevertsUnderRevm(string memory destKey) internal {
        CCTPUSDCDemo.Dest memory d = probe.dest(destKey);
        address hub = probe.setupHub(actor, 0, 2000);

        // Arc USDC is a 6-decimal view over the native balance (balanceOf = balance / 1e12); fund natively.
        vm.deal(actor, AMOUNT * 1e12);
        assertEq(IERC20(ARC_USDC).balanceOf(actor), AMOUNT, "funded exactly AMOUNT on the ERC-20 view");

        // The balance guard passes; the burn then reverts inside `pullExact` when the native-move precompile
        // is invoked under revm — bubbled as BridgeTransferFailed(ARC_USDC).
        vm.expectRevert(abi.encodeWithSelector(IBridgeFungible.BridgeTransferFailed.selector, ARC_USDC));
        probe.cctpDemoBurnStep(d, hub, actor, AMOUNT);

        // The reverted call rolls back entirely: funds are safe, no allowance stranded.
        assertEq(IERC20(ARC_USDC).balanceOf(actor), AMOUNT, "revert rolled back: nothing debited");
        assertEq(IERC20(ARC_USDC).allowance(hub, TOKEN_MESSENGER_V2), 0, "no messenger allowance left behind");
    }

    /// @notice The burn NEVER pulls partially: a short balance reverts BEFORE any approval or transfer. This
    ///         guard reads `balanceOf` (which DOES simulate on Arc), so it fires even though a full burn cannot.
    function test_Fork_BurnRevertsOnInsufficientUSDCWithoutPulling() public {
        CCTPUSDCDemo.Dest memory d = probe.dest("sepolia");
        address hub = probe.setupHub(actor, 0, 2000);

        vm.deal(actor, (AMOUNT - 1) * 1e12);
        vm.expectRevert(
            abi.encodeWithSelector(CCTPUSDCDemo.CCTPUSDCDemo__InsufficientUSDC.selector, AMOUNT - 1, AMOUNT)
        );
        probe.cctpDemoBurnStep(d, hub, actor, AMOUNT);

        assertEq(IERC20(ARC_USDC).balanceOf(actor), AMOUNT - 1, "not one token pulled");
        assertEq(IERC20(ARC_USDC).allowance(hub, TOKEN_MESSENGER_V2), 0, "no approval left behind");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                 STATUS — machine-readable tuple across phases
    //////////////////////////////////////////////////////////////////////////*//

    function test_Fork_StatusTupleAcrossPhases_Sepolia() public {
        _statusTupleAcrossPhases("sepolia");
    }

    function test_Fork_StatusTupleAcrossPhases_Base() public {
        _statusTupleAcrossPhases("base");
    }

    function _statusTupleAcrossPhases(string memory destKey) internal {
        CCTPUSDCDemo.Dest memory d = probe.dest(destKey);
        if (!_dstRpcReady(_dstRpcVar(d))) return;

        // Fresh: no hub -> NEEDS-SETUP.
        (uint8 phase,, uint256 done,,) = probe.demoStatus(address(0), actor, AMOUNT, d, 0, 0);
        assertEq(phase, 0, "fresh -> NEEDS-SETUP");
        assertEq(done, 0, "not done");

        // Assemble the hub on Arc (NOT funded yet); carry it across the live-tip status forks.
        _forkArc();
        address hub = probe.setupHub(actor, 0, 2000);
        _persist(hub);
        vm.makePersistent(ARC_USDC);

        // Wired but the actor is UNFUNDED on Arc -> NEEDS-FUNDS (the funding gate). The probe holds no Arc USDC
        // on the live-tip Arc fork, so srcBal 0 < AMOUNT.
        uint256 waitSeconds;
        uint256 srcBal;
        (phase, waitSeconds, done, srcBal,) = probe.demoStatus(hub, actor, AMOUNT, d, 0, 0);
        assertEq(phase, 1, "wired but unfunded -> NEEDS-FUNDS");
        assertEq(waitSeconds, 0, "funding is a human gate, not a timed wait");
        assertEq(done, 0, "not done");
        assertEq(srcBal, 0, "source unfunded");

        // Fund the source natively on Arc (the persistent actor carries the balance across the status re-forks).
        _forkArc();
        vm.deal(actor, AMOUNT * 1e12);

        // Funded, not yet burned -> READY-TO-BURN, srcBal == AMOUNT.
        (phase, waitSeconds, done, srcBal,) = probe.demoStatus(hub, actor, AMOUNT, d, 0, 0);
        assertEq(phase, 2, "funded -> READY-TO-BURN");
        assertEq(waitSeconds, 0, "actionable now");
        assertEq(done, 0, "not done");
        assertEq(srcBal, AMOUNT, "source balance is the funded amount");

        // Burned (loop-carried burned=1), destination not yet credited (baseline 0) -> AWAITING-DELIVERY.
        (phase, waitSeconds, done,,) = probe.demoStatus(hub, actor, AMOUNT, d, 1, 0);
        assertEq(phase, 3, "burned, undelivered -> AWAITING-DELIVERY");
        assertEq(waitSeconds, 30, "poll hint");
        assertEq(done, 0, "not done");

        // Simulate the destination mint -> DELIVERED. Destination USDC is a normal ERC-20 (stdstore deal works);
        // relay gas is ETH, never netted from the credit, so DELIVERED is simply dstBal >= baseline + AMOUNT
        // (free standard burn: srcMaxFee 0). Persist the token so the deal survives the live-tip status re-fork.
        _forkDest(d);
        vm.makePersistent(d.usdc);
        deal(d.usdc, actor, AMOUNT);

        uint256 dstBal;
        (phase, waitSeconds, done,, dstBal) = probe.demoStatus(hub, actor, AMOUNT, d, 1, 0);
        assertEq(phase, 4, "delivered -> DELIVERED");
        assertEq(waitSeconds, 0, "delivered needs nothing");
        assertEq(done, 1, "done");
        assertEq(dstBal, AMOUNT, "destination credited the full free-standard amount");
    }
}
