// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {CCTPUSDCDemo} from "@lattice-script/base/crosschain/CCTPUSDCDemo.s.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Exposes {CCTPUSDCDemo}'s broadcast-free internals so tests assert the parsed values directly
///         instead of scraping console output (the probe idiom of the governance-demo fork suites). Stateless
///         over the lane/diamonds, so one probe serves every lane and phase.
contract CCTPUSDCDemoProbe is CCTPUSDCDemo {
    function lane(string calldata key) external pure returns (Lane memory) {
        return _lane(key);
    }

    function setupSide(Lane memory l, bool source, address admin, uint256 maxFee, uint32 minFinality)
        external
        returns (address)
    {
        return _setupSide(l, source, admin, maxFee, minFinality);
    }

    function demoStatus(
        Lane memory l,
        address srcDiamond,
        address dstDiamond,
        address actor,
        uint256 amount,
        uint256 burned,
        uint256 dstBaseline
    ) external returns (uint8 phase, uint256 waitSeconds, uint256 done, uint256 srcBal, uint256 dstBal) {
        return _demoStatus(l, srcDiamond, dstDiamond, actor, amount, burned, dstBaseline);
    }
}

/// @title CCTPUSDCDemoFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice MULTI-CHAIN fork proof of the {CCTPUSDCDemo} self-cranking CCTP v2 USDC runbook: assembles the
///         production {DeployCCTPBridgeAdapter} diamond on BOTH sides of a lane across two live forks, burns
///         REAL testnet USDC through the LIVE Sepolia `TokenMessengerV2`, and asserts the machine-readable
///         status tuple across every phase. Two lanes are exercised independently: `base` (Sepolia -> Base
///         Sepolia) and `arc` (Sepolia -> Arc testnet).
///
/// Enabling:
///   export SEPOLIA_RPC_URL=<...>            # required for EVERY test here (the burn source)
///   export BASE_SEPOLIA_RPC_URL=<...>       # enables the *_Base lane tests
///   export ARC_TESTNET_RPC_URL=<...>        # enables the *_Arc  lane tests
///   forge test --match-path "test/fork/CCTPUSDCDemoFork.t.sol"
///
/// Without SEPOLIA_RPC_URL the whole suite skips; each lane test additionally skips if its destination RPC is
/// unset. Fork blocks are pinned (overridable via <ALIAS>_FORK_BLOCK) so runs reproduce and the RPC cache hits;
/// {CCTPUSDCDemo._demoStatus} itself forks at the LIVE tip (status is inherently current), and the deployed
/// diamonds + dealt balances are carried across those forks with `vm.makePersistent`.
contract CCTPUSDCDemoFork is Test {
    /// @notice Circle CCTP v2 `TokenMessengerV2` on every testnet (asserted allowance target after a burn).
    address internal constant TOKEN_MESSENGER_V2 = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;
    /// @notice USDC on Ethereum Sepolia — the burn source of funds.
    address internal constant SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    /// @notice Pinned fork blocks (overridable via env). Sepolia matches the other Lattice fork suites; the
    ///         destination defaults are recent testnet heights — bump them (or set <ALIAS>_FORK_BLOCK) if an
    ///         RPC prunes state before them. `_demoStatus` forks at the live tip regardless.
    uint256 internal constant DEFAULT_SEPOLIA_FORK_BLOCK = 11_239_288;
    uint256 internal constant DEFAULT_BASE_SEPOLIA_FORK_BLOCK = 21_000_000;
    uint256 internal constant DEFAULT_ARC_TESTNET_FORK_BLOCK = 5_000_000;

    uint256 internal constant AMOUNT = 1_000_000; // 1 USDC (6 decimals)

    CCTPUSDCDemoProbe internal probe;
    address internal actor; // the probe instance — the sender of every broadcast-free sub-call

    function setUp() public {
        if (bytes(vm.envOr("SEPOLIA_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        _forkSepolia();
        probe = new CCTPUSDCDemoProbe();
        actor = address(probe);
        // Tests, unlike scripts, do NOT auto-persist helpers across forks — the probe must survive re-forking.
        vm.makePersistent(address(probe));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    function _forkSepolia() internal {
        vm.createSelectFork("sepolia", vm.envOr("SEPOLIA_FORK_BLOCK", DEFAULT_SEPOLIA_FORK_BLOCK));
    }

    function _forkDst(CCTPUSDCDemo.Lane memory lane) internal {
        if (keccak256(bytes(lane.dstAlias)) == keccak256("base-sepolia")) {
            vm.createSelectFork(lane.dstAlias, vm.envOr("BASE_SEPOLIA_FORK_BLOCK", DEFAULT_BASE_SEPOLIA_FORK_BLOCK));
        } else {
            vm.createSelectFork(lane.dstAlias, vm.envOr("ARC_TESTNET_FORK_BLOCK", DEFAULT_ARC_TESTNET_FORK_BLOCK));
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

    /// @dev Carries a freshly-deployed diamond (proxy + every loupe-reported facet) across future forks.
    function _persist(address diamond) internal {
        vm.makePersistent(diamond);
        address[] memory facets = IDiamondLoupe(diamond).facetAddresses();
        for (uint256 i; i < facets.length; ++i) {
            vm.makePersistent(facets[i]);
        }
    }

    /// @dev Symmetric wiring assertions for one side of a lane (diamond active on the current fork).
    function _assertSide(address diamond, address expectedUsdc, uint256 counterpartyChainId, uint32 counterpartyDomain)
        internal
        view
    {
        assertEq(ICCTPBridgeAdapter(diamond).usdc(), expectedUsdc, "usdc() wired to the lane token");
        assertEq(ICCTPBridgeAdapter(diamond).tokenMessenger(), TOKEN_MESSENGER_V2, "tokenMessenger() wired");
        assertTrue(ICCTPBridgeAdapter(diamond).isChainRegistered(counterpartyChainId), "counterparty registered");
        assertEq(ICCTPBridgeAdapter(diamond).getDomain(counterpartyChainId), counterpartyDomain, "domain mapped");
        (uint256 maxFee, uint32 minFinality, bytes32 destCaller) =
            ICCTPBridgeAdapter(diamond).getDomainConfig(counterpartyDomain);
        assertEq(maxFee, 0, "standard free burn: maxFee 0");
        assertEq(minFinality, 2000, "standard finality threshold");
        assertEq(destCaller, bytes32(0), "permissionless mint");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     SETUP — both diamonds across two forks
    //////////////////////////////////////////////////////////////////////////*//

    function test_Fork_SetupAssemblesBothDiamondsAcrossForks_Base() public {
        _setupAssemblesBothDiamonds("base");
    }

    function test_Fork_SetupAssemblesBothDiamondsAcrossForks_Arc() public {
        _setupAssemblesBothDiamonds("arc");
    }

    function _setupAssemblesBothDiamonds(string memory laneKey) internal {
        CCTPUSDCDemo.Lane memory lane = probe.lane(laneKey);
        if (keccak256(bytes(lane.dstAlias)) == keccak256("base-sepolia")) {
            if (!_dstRpcReady("BASE_SEPOLIA_RPC_URL")) return;
        } else if (!_dstRpcReady("ARC_TESTNET_RPC_URL")) {
            return;
        }

        // Source side (Sepolia fork from setUp): assert its wiring before switching forks.
        address src = probe.setupSide(lane, true, actor, 0, 2000);
        _assertSide(src, lane.srcUsdc, lane.dstChainId, lane.dstDomain);

        // Destination side on the other fork: symmetric wiring toward the source counterparty.
        _forkDst(lane);
        address dst = probe.setupSide(lane, false, actor, 0, 2000);
        _assertSide(dst, lane.dstUsdc, lane.srcChainId, lane.srcDomain);

        assertTrue(src != dst, "distinct diamonds per side");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     BURN — real testnet USDC on the Sepolia fork
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Burns REAL Sepolia USDC through the LIVE `TokenMessengerV2`: CCTP v2 burns the FULL amount on
    ///         the source (the fee is taken at mint on the destination), so the observable is the USDC
    ///         `totalSupply` dropping by exactly `AMOUNT`, with no allowance or balance stranded on the diamond.
    function test_Fork_BurnMovesRealTestnetUSDCOnSepoliaFork() public {
        CCTPUSDCDemo.Lane memory lane = probe.lane("base"); // domain 6 is wired on the live Sepolia messenger
        address src = probe.setupSide(lane, true, actor, 0, 2000);

        deal(SEPOLIA_USDC, actor, AMOUNT);
        uint256 supplyBefore = IERC20(SEPOLIA_USDC).totalSupply();

        probe.cctpDemoBurnStep(lane, src, actor, AMOUNT);

        assertEq(IERC20(SEPOLIA_USDC).balanceOf(actor), 0, "actor debited exactly AMOUNT");
        assertEq(supplyBefore - IERC20(SEPOLIA_USDC).totalSupply(), AMOUNT, "CCTP v2 burns the full amount");
        assertEq(IERC20(SEPOLIA_USDC).allowance(src, TOKEN_MESSENGER_V2), 0, "messenger allowance reset to 0");
        assertEq(IERC20(SEPOLIA_USDC).balanceOf(src), 0, "no USDC stuck on the diamond");
    }

    /// @notice The burn NEVER pulls partially: a short balance reverts BEFORE any approval or transfer.
    function test_Fork_BurnRevertsOnInsufficientUSDCWithoutPulling() public {
        CCTPUSDCDemo.Lane memory lane = probe.lane("base");
        address src = probe.setupSide(lane, true, actor, 0, 2000);

        deal(SEPOLIA_USDC, actor, AMOUNT - 1);
        vm.expectRevert(
            abi.encodeWithSelector(CCTPUSDCDemo.CCTPUSDCDemo__InsufficientUSDC.selector, AMOUNT - 1, AMOUNT)
        );
        probe.cctpDemoBurnStep(lane, src, actor, AMOUNT);

        assertEq(IERC20(SEPOLIA_USDC).balanceOf(actor), AMOUNT - 1, "not one token pulled");
        assertEq(IERC20(SEPOLIA_USDC).allowance(src, TOKEN_MESSENGER_V2), 0, "no approval left behind");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                 STATUS — machine-readable tuple across phases
    //////////////////////////////////////////////////////////////////////////*//

    function test_Fork_StatusTupleAcrossPhases_Base() public {
        _statusTupleAcrossPhases("base");
    }

    function test_Fork_StatusTupleAcrossPhases_Arc() public {
        _statusTupleAcrossPhases("arc");
    }

    function _statusTupleAcrossPhases(string memory laneKey) internal {
        CCTPUSDCDemo.Lane memory lane = probe.lane(laneKey);
        if (keccak256(bytes(lane.dstAlias)) == keccak256("base-sepolia")) {
            if (!_dstRpcReady("BASE_SEPOLIA_RPC_URL")) return;
        } else if (!_dstRpcReady("ARC_TESTNET_RPC_URL")) {
            return;
        }

        // Fresh: no diamonds -> NEEDS-SETUP.
        (uint8 phase,, uint256 done,,) = probe.demoStatus(lane, address(0), address(0), actor, AMOUNT, 0, 0);
        assertEq(phase, 0, "fresh -> NEEDS-SETUP");
        assertEq(done, 0, "not done");

        // Assemble both sides and fund the source; carry them across the live-tip status forks.
        _forkSepolia();
        address src = probe.setupSide(lane, true, actor, 0, 2000);
        _persist(src);
        vm.makePersistent(lane.srcUsdc);
        deal(lane.srcUsdc, actor, AMOUNT);

        _forkDst(lane);
        address dst = probe.setupSide(lane, false, actor, 0, 2000);
        _persist(dst);
        vm.makePersistent(lane.dstUsdc);

        // Setup + funded, not yet burned -> READY-TO-BURN, srcBal == AMOUNT.
        uint256 waitSeconds;
        uint256 srcBal;
        (phase, waitSeconds, done, srcBal,) = probe.demoStatus(lane, src, dst, actor, AMOUNT, 0, 0);
        assertEq(phase, 2, "funded -> READY-TO-BURN");
        assertEq(waitSeconds, 0, "actionable now");
        assertEq(done, 0, "not done");
        assertEq(srcBal, AMOUNT, "source balance is the funded amount");

        // Burned (loop-carried burned=1), destination not yet credited (baseline 0) -> AWAITING-DELIVERY.
        (phase, waitSeconds, done,,) = probe.demoStatus(lane, src, dst, actor, AMOUNT, 1, 0);
        assertEq(phase, 3, "burned, undelivered -> AWAITING-DELIVERY");
        assertEq(waitSeconds, 30, "poll hint");
        assertEq(done, 0, "not done");

        // Simulate the destination mint (maxFee 0 -> the recipient nets the full AMOUNT) -> DELIVERED.
        _forkDst(lane);
        deal(lane.dstUsdc, actor, AMOUNT);
        uint256 dstBal;
        (phase, waitSeconds, done,, dstBal) = probe.demoStatus(lane, src, dst, actor, AMOUNT, 1, 0);
        assertEq(phase, 4, "delivered -> DELIVERED");
        assertEq(waitSeconds, 0, "delivered needs nothing");
        assertEq(done, 1, "done");
        assertGe(dstBal, AMOUNT, "destination credited at least AMOUNT");
    }
}
