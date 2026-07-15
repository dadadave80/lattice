// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployCCTPBridgeAdapter} from "@lattice-script/base/crosschain/DeployCCTPBridgeAdapter.s.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {console} from "forge-std/Script.sol";

/// @title CCTPUSDCDemo
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice SELF-CRANKING, MULTI-CHAIN Circle CCTP v2 USDC demo: moves REAL testnet USDC through Lattice
///         {DeployCCTPBridgeAdapter} diamonds on two lanes out of Ethereum Sepolia — `arc` (Sepolia -> Arc
///         testnet) and `base` (Sepolia -> Base Sepolia) — extending the parent recipe exactly as
///         {DeployGovernedVaultENS} extends {DeployGovernedVault}. CCTP is BURN-AND-MINT: USDC is burned on
///         the source chain, an off-chain Iris attestation is fetched, then the message is relayed on the
///         destination which mints the USDC. `forge script` is collect-then-dispatch (every broadcast fires
///         AFTER the body returns), so ONE run cannot burn -> attest -> relay: the attestation only exists
///         once the burn is mined. The demo is therefore a CRANK STATE MACHINE across runs, and the loop
///         (script/config/cctp-usdc-demo-loop.sh) owns the off-chain journal (burn tx hash, Iris message,
///         attestation) between cranks. Each entrypoint drives ONLY the existing adapter surface
///         (`depositForBurn` + `relayMessage` + `registerChainDomain` / `configureDomain`); no src/ contract
///         is modified. TESTNET-ONLY.
/// @dev RUNBOOK — <actor> = your keystore address; FORGE_AUTH='--account <name>'
///  0. Fund via https://faucet.circle.com : Sepolia USDC -> actor (>= 1 USDC) + Sepolia ETH;
///     arc lane: Arc testnet USDC (gas) -> actor; base lane: Base Sepolia ETH -> actor.
///  1. Run a lane end-to-end (setup -> burn -> Iris attest -> relay -> verify, unattended):
///     FORGE_AUTH='--account <name>' script/config/cctp-usdc-demo-loop.sh arc  <actor>
///     FORGE_AUTH='--account <name>' script/config/cctp-usdc-demo-loop.sh base <actor>
///  2. Manual per-step equivalents:
///     forge script script/base/crosschain/CCTPUSDCDemo.s.sol:CCTPUSDCDemo --account <name> --broadcast --verify \
///       --sig "cctpDemoSetup(string,uint256,uint32)" arc 0 2000
///     (status is broadcast-free: --sig "cctpDemoStatus(string,address,address,address,uint256,uint256,uint256)"
///        arc <src> <dst> <actor> 1000000 0 0)
///  3. Deploys auto-verify via Sourcify (Foundry's default verifier) — the setup command already includes
///     `--verify`; no API key needed. (Multichain `--verify` verifies each chain by chain-id; a chain not on
///     Sourcify fails that one contract non-fatally.)
///  Explorers: sepolia.etherscan.io · sepolia.basescan.org · testnet.arcscan.app
contract CCTPUSDCDemo is DeployCCTPBridgeAdapter {
    //*//////////////////////////////////////////////////////////////////////////
    //                        CCTP v2 TESTNET CONTRACTS (SAME ON EVERY TESTNET)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Circle CCTP v2 `TokenMessengerV2` — identical address on every testnet (Sepolia, Base, Arc).
    address internal constant TOKEN_MESSENGER_V2 = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;

    /// @notice Circle CCTP v2 `MessageTransmitterV2` — identical address on every testnet.
    address internal constant MESSAGE_TRANSMITTER_V2 = 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275;

    /// @notice USDC on Ethereum Sepolia (CCTP domain 0, chain 11155111) — the burn source on every lane.
    address internal constant SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    /// @notice USDC on Base Sepolia (CCTP domain 6, chain 84532).
    address internal constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    /// @notice USDC on Arc testnet (CCTP domain 26, chain 5042002) — the NATIVE gas token, exposed as a
    ///         6-decimal ERC-20 view at this address (which carries bytecode / is a proxy).
    address internal constant ARC_USDC = 0x3600000000000000000000000000000000000000;

    /// @notice DELIVERED slack (USDC units) subtracted from the credited threshold on a lane whose destination
    ///         USDC is the NATIVE gas token: the actor signs the relay, so its relay gas is debited from the
    ///         very balance `balanceOf` views. Without this the mint's `amount` credit is netted against gas
    ///         and DELIVERED (`dstBal >= baseline + amount`) can never be reached. 50_000 = 0.05 USDC
    ///         (6-dec; ~200k gas @ 20 gwei on a 1e12-scaled native view ≈ 4,000 units — a comfortable ceiling).
    uint256 internal constant DST_NATIVE_GAS_ALLOWANCE = 50_000;

    //*//////////////////////////////////////////////////////////////////////////
    //                               LANE PRESETS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A hardcoded Sepolia -> destination lane. `srcUsdc` is always Sepolia USDC (domain 0).
    struct Lane {
        string srcAlias;
        string dstAlias;
        uint256 srcChainId;
        uint256 dstChainId;
        uint32 srcDomain;
        uint32 dstDomain;
        address srcUsdc;
        address dstUsdc;
        bool dstUsdcIsNative;
    }

    /// @notice Thrown when the lane key is neither `"arc"` nor `"base"`.
    error CCTPUSDCDemo__UnknownLane(string key);

    /// @notice Thrown when the actor's source USDC balance is below `amount` — the burn never pulls partially.
    error CCTPUSDCDemo__InsufficientUSDC(uint256 balance, uint256 required);

    /// @notice Resolves the hardcoded lane preset for `key` (`"arc"` or `"base"`); reverts on any other key.
    function _lane(string memory key) internal pure returns (Lane memory lane) {
        bytes32 k = keccak256(bytes(key));
        if (k == keccak256("arc")) {
            lane = Lane({
                srcAlias: "sepolia",
                dstAlias: "arc-testnet",
                srcChainId: 11_155_111,
                dstChainId: 5_042_002,
                srcDomain: 0,
                dstDomain: 26,
                srcUsdc: SEPOLIA_USDC,
                dstUsdc: ARC_USDC,
                dstUsdcIsNative: true
            });
        } else if (k == keccak256("base")) {
            lane = Lane({
                srcAlias: "sepolia",
                dstAlias: "base-sepolia",
                srcChainId: 11_155_111,
                dstChainId: 84_532,
                srcDomain: 0,
                dstDomain: 6,
                srcUsdc: SEPOLIA_USDC,
                dstUsdc: BASE_SEPOLIA_USDC,
                dstUsdcIsNative: false
            });
        } else {
            revert CCTPUSDCDemo__UnknownLane(key);
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          CRANK ENTRYPOINTS (BROADCAST)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice MULTICHAIN setup crank: assembles a CCTP adapter diamond on BOTH the source (Sepolia) and the
    ///         destination fork, wiring each side's counterparty chain -> domain equivalence and per-domain
    ///         burn config. `msg.sender` (the keystore signer) is the admin of both diamonds. Prints
    ///         `DEMO-SETUP <srcDiamond> <dstDiamond>` — the loop reads the two addresses from THIS console
    ///         line (a multichain run's diamonds are not addressable from a single broadcast JSON).
    /// @param laneKey             The lane preset key (`"arc"` or `"base"`).
    /// @param maxFee              The per-domain CCTP `maxFee` (0 = free standard transfer).
    /// @param minFinalityThreshold The finality threshold (2000 standard-finalized, 1000 fast).
    function cctpDemoSetup(string calldata laneKey, uint256 maxFee, uint32 minFinalityThreshold) external {
        Lane memory lane = _lane(laneKey);
        address admin = msg.sender;

        vm.createSelectFork(lane.srcAlias);
        vm.startBroadcast();
        address srcDiamond = _setupSide(lane, true, admin, maxFee, minFinalityThreshold);
        vm.stopBroadcast();

        vm.createSelectFork(lane.dstAlias);
        vm.startBroadcast();
        address dstDiamond = _setupSide(lane, false, admin, maxFee, minFinalityThreshold);
        vm.stopBroadcast();

        console.log(string.concat("DEMO-SETUP ", vm.toString(srcDiamond), " ", vm.toString(dstDiamond)));
    }

    /// @notice READ-ONLY status crank (broadcast-free — invoked WITHOUT `--broadcast`, a dry-run simulation):
    ///         creates the source fork and reads the actor's source USDC balance + the source diamond wiring,
    ///         then creates the destination fork and reads the actor's destination USDC balance. Prints ONE
    ///         line `DEMO-STATUS <phase> <waitSeconds> <done> <srcBal> <dstBal>` the loop parses to decide
    ///         crank-vs-sleep. NON-VIEW because fork cheatcodes are non-view.
    /// @dev Post-burn the source balance drops, so the contract alone cannot tell NEEDS-FUNDS from a completed
    ///      burn — the loop carries `burned` (0/1) and `dstBaseline` (the destination balance recorded at burn
    ///      time) so status can classify the delivery phase. This division of labor is deliberate.
    /// @param laneKey     The lane preset key.
    /// @param srcDiamond  The source (Sepolia) adapter diamond.
    /// @param dstDiamond  The destination adapter diamond.
    /// @param actor       The address whose USDC balances are read (the keystore signer).
    /// @param amount      The burn amount (6-decimal USDC units).
    /// @param burned      0 before the burn is mined, 1 after (loop-carried).
    /// @param dstBaseline The destination USDC balance of `actor` recorded at burn time (loop-carried).
    function cctpDemoStatus(
        string calldata laneKey,
        address srcDiamond,
        address dstDiamond,
        address actor,
        uint256 amount,
        uint256 burned,
        uint256 dstBaseline
    ) external {
        Lane memory lane = _lane(laneKey);
        (uint8 phase, uint256 waitSeconds, uint256 done, uint256 srcBal, uint256 dstBal) =
            _demoStatus(lane, srcDiamond, dstDiamond, actor, amount, burned, dstBaseline);
        console.log(
            string.concat(
                "DEMO-STATUS ",
                vm.toString(phase),
                " ",
                vm.toString(waitSeconds),
                " ",
                vm.toString(done),
                " ",
                vm.toString(srcBal),
                " ",
                vm.toString(dstBal)
            )
        );
    }

    /// @notice BURN crank (source fork only): pulls exactly `amount` USDC from `msg.sender` and burns it
    ///         through the source diamond toward `msg.sender` on the destination chain (recipient == the
    ///         signer). Reverts {CCTPUSDCDemo__InsufficientUSDC} BEFORE any approval if the signer's balance
    ///         is short — never a partial pull. Prints `DEMO-BURN <recipient> <amount>`.
    function cctpDemoBurn(string calldata laneKey, address srcDiamond, uint256 amount) external {
        Lane memory lane = _lane(laneKey);
        address actor = msg.sender;

        vm.createSelectFork(lane.srcAlias);
        vm.startBroadcast();
        cctpDemoBurnStep(lane, srcDiamond, actor, amount);
        vm.stopBroadcast();

        console.log(string.concat("DEMO-BURN ", vm.toString(actor), " ", vm.toString(amount)));
    }

    /// @notice RELAY crank (destination fork only): forwards the Iris-attested CCTP `message` + `attestation`
    ///         to the destination diamond's permissionless `relayMessage`, minting the bridged USDC to the
    ///         recipient. Prints `DEMO-RELAY <recipientBalanceAfter>`.
    function cctpDemoRelay(
        string calldata laneKey,
        address dstDiamond,
        bytes calldata message,
        bytes calldata attestation
    ) external {
        Lane memory lane = _lane(laneKey);
        address actor = msg.sender;

        vm.createSelectFork(lane.dstAlias);
        vm.startBroadcast();
        ICCTPBridgeAdapter(dstDiamond).relayMessage(message, attestation);
        vm.stopBroadcast();

        console.log(string.concat("DEMO-RELAY ", vm.toString(IERC20(lane.dstUsdc).balanceOf(actor))));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     BROADCAST-FREE INTERNALS (SHARED WITH TESTS)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Assembles ONE side's CCTP adapter diamond and wires its counterparty domain (broadcast-free —
    ///         the crank entrypoints wrap this in `vm.startBroadcast()`; tests call it on a selected fork).
    /// @param lane        The resolved lane preset.
    /// @param source      True to build the Sepolia source side, false to build the destination side.
    /// @param admin       The address granted `DEFAULT_ADMIN_ROLE` (must be the caller of the register/config
    ///                     sub-calls — the broadcaster under `--broadcast`, or the probe in a test).
    /// @param maxFee      The per-domain CCTP `maxFee`.
    /// @param minFinality The per-domain CCTP `minFinalityThreshold`.
    /// @return diamond The assembled adapter diamond, its counterparty already registered + configured.
    function _setupSide(Lane memory lane, bool source, address admin, uint256 maxFee, uint32 minFinality)
        internal
        returns (address diamond)
    {
        address localUsdc = source ? lane.srcUsdc : lane.dstUsdc;
        uint256 counterpartyChainId = source ? lane.dstChainId : lane.srcChainId;
        uint32 counterpartyDomain = source ? lane.dstDomain : lane.srcDomain;

        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(admin, TOKEN_MESSENGER_V2, MESSAGE_TRANSMITTER_V2, localUsdc);
        diamond = _assemble(cuts, init, initCalldata);

        ICCTPBridgeAdapter(diamond).registerChainDomain(counterpartyChainId, counterpartyDomain);
        ICCTPBridgeAdapter(diamond).configureDomain(counterpartyDomain, maxFee, minFinality, bytes32(0));
    }

    /// @notice One broadcast-free burn: balance-checks `actor`, approves the source diamond for exactly
    ///         `amount`, and burns toward `actor` on the destination chain (ERC-7930 recipient). Tests drive
    ///         this directly; the {cctpDemoBurn} wrapper drives it under broadcast with `actor == msg.sender`.
    function cctpDemoBurnStep(Lane memory lane, address srcDiamond, address actor, uint256 amount) public {
        uint256 balance = IERC20(lane.srcUsdc).balanceOf(actor);
        if (balance < amount) revert CCTPUSDCDemo__InsufficientUSDC(balance, amount);

        IERC20(lane.srcUsdc).approve(srcDiamond, amount);
        ICCTPBridgeAdapter(srcDiamond).depositForBurn(amount, InteroperableAddress.formatEvmV1(lane.dstChainId, actor));
    }

    /// @notice The cross-fork status computation {cctpDemoStatus} prints, exposed so tests read the values
    ///         directly instead of parsing console output. Creates the source fork (LIVE tip) to read the
    ///         source wiring + `actor`'s source balance, then the destination fork to read `actor`'s
    ///         destination balance, then classifies the phase.
    /// @return phase       0 NEEDS-SETUP, 1 NEEDS-FUNDS, 2 READY-TO-BURN, 3 AWAITING-DELIVERY, 4 DELIVERED.
    /// @return waitSeconds A poll hint (30 while awaiting delivery, else 0 — actionable now).
    /// @return done        1 only when DELIVERED.
    /// @return srcBal      `actor`'s source USDC balance.
    /// @return dstBal      `actor`'s destination USDC balance.
    function _demoStatus(
        Lane memory lane,
        address srcDiamond,
        address dstDiamond,
        address actor,
        uint256 amount,
        uint256 burned,
        uint256 dstBaseline
    ) internal returns (uint8 phase, uint256 waitSeconds, uint256 done, uint256 srcBal, uint256 dstBal) {
        bool srcReady;
        uint256 deliveredThreshold;
        (srcReady, srcBal, deliveredThreshold) = _srcSide(lane, srcDiamond, actor, amount, dstBaseline);

        bool dstReady;
        (dstReady, dstBal) = _dstSide(lane, dstDiamond, actor);

        (phase, waitSeconds, done) =
            _computePhase(srcReady && dstReady, amount, burned, srcBal, dstBal, deliveredThreshold);
    }

    /// @dev Creates the SOURCE fork (LIVE tip) and reads its readiness, `actor`'s source balance, and the
    ///      DELIVERED threshold `dstBaseline + net`, where `net = amount - srcMaxFee` (fee-adjusted,
    ///      underflow-guarded) less {DST_NATIVE_GAS_ALLOWANCE} when the destination USDC is the native gas
    ///      token (the actor's relay gas is debited from the same balance `balanceOf` views). A floor of 1
    ///      keeps DELIVERED requiring a real credit above the baseline.
    function _srcSide(Lane memory lane, address srcDiamond, address actor, uint256 amount, uint256 dstBaseline)
        private
        returns (bool srcReady, uint256 srcBal, uint256 deliveredThreshold)
    {
        vm.createSelectFork(lane.srcAlias);
        srcReady = _sideReady(srcDiamond, lane.srcUsdc, lane.dstChainId);
        srcBal = IERC20(lane.srcUsdc).balanceOf(actor);
        uint256 srcMaxFee = srcReady ? _domainMaxFee(srcDiamond, lane.dstDomain) : 0;
        uint256 net = amount > srcMaxFee ? amount - srcMaxFee : 0;
        if (lane.dstUsdcIsNative) net = net > DST_NATIVE_GAS_ALLOWANCE ? net - DST_NATIVE_GAS_ALLOWANCE : 1;
        deliveredThreshold = dstBaseline + net;
    }

    /// @dev Creates the DESTINATION fork (LIVE tip) and reads its readiness + `actor`'s destination balance.
    function _dstSide(Lane memory lane, address dstDiamond, address actor)
        private
        returns (bool dstReady, uint256 dstBal)
    {
        vm.createSelectFork(lane.dstAlias);
        dstReady = _sideReady(dstDiamond, lane.dstUsdc, lane.srcChainId);
        dstBal = IERC20(lane.dstUsdc).balanceOf(actor);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              PHASE COMPUTATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Classifies the demo phase from both sides' readiness, the loop-carried burn flag, and balances.
    /// @dev `deliveredThreshold` is `dstBaseline + (amount - srcMaxFee)`: CCTP burns the full `amount` on the
    ///      source and takes the fee (<= `srcMaxFee`) at mint time, so the recipient nets at least this much.
    function _computePhase(
        bool ready,
        uint256 amount,
        uint256 burned,
        uint256 srcBal,
        uint256 dstBal,
        uint256 deliveredThreshold
    ) internal pure returns (uint8 phase, uint256 waitSeconds, uint256 done) {
        if (!ready) return (0, 0, 0); // NEEDS-SETUP

        if (burned == 0) {
            if (srcBal < amount) return (1, 0, 0); // NEEDS-FUNDS
            return (2, 0, 0); // READY-TO-BURN
        }

        if (dstBal < deliveredThreshold) return (3, 30, 0); // AWAITING-DELIVERY
        return (4, 0, 1); // DELIVERED
    }

    /// @notice True when `diamond` is a live CCTP adapter whose `usdc()` matches `expectedUsdc` and which has
    ///         registered `counterpartyChainId`. Guards against a codeless / mismatched / unregistered side.
    function _sideReady(address diamond, address expectedUsdc, uint256 counterpartyChainId)
        internal
        view
        returns (bool)
    {
        if (diamond.code.length == 0) return false;
        try ICCTPBridgeAdapter(diamond).usdc() returns (address u) {
            if (u != expectedUsdc) return false;
        } catch {
            return false;
        }
        try ICCTPBridgeAdapter(diamond).isChainRegistered(counterpartyChainId) returns (bool registered) {
            return registered;
        } catch {
            return false;
        }
    }

    /// @dev The source diamond's `maxFee` for burns toward `domain` (the ceiling on the destination-side fee).
    function _domainMaxFee(address diamond, uint32 domain) internal view returns (uint256 maxFee) {
        (maxFee,,) = ICCTPBridgeAdapter(diamond).getDomainConfig(domain);
    }
}
