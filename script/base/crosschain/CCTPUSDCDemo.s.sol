// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployCCTPBridgeAdapter} from "@lattice-script/base/crosschain/DeployCCTPBridgeAdapter.s.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {IReceiverV2} from "@lattice/interfaces/external/circle/IReceiverV2.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {console} from "forge-std/Script.sol";

/// @title CCTPUSDCDemo
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice SELF-CRANKING Circle CCTP v2 USDC demo built as an ARC HUB: ONE Lattice
///         {DeployCCTPBridgeAdapter} diamond is deployed on Circle's Arc testnet (the SOURCE) with a two-entry
///         domain table, and it bridges REAL testnet USDC OUT to BOTH Ethereum Sepolia AND Base Sepolia. CCTP
///         is BURN-AND-MINT: USDC is burned on the source (Arc), an off-chain Iris attestation is fetched, then
///         the message is relayed on the destination which mints the USDC. `forge script` is
///         collect-then-dispatch (every broadcast fires AFTER the body returns), so ONE run cannot
///         burn -> attest -> relay: the attestation only exists once the burn is mined. The demo is therefore a
///         CRANK STATE MACHINE across runs, and the loop (script/config/cctp-usdc-demo-loop.sh) owns the
///         off-chain journal (hub address, per-dest burn tx hash, Iris message, attestation) between cranks.
///
///         WHY ARC AS THE SOURCE HUB (both facts established on live chains):
///          - SPEED. Standard (free) CCTP attests only after SOURCE-chain hard finality. Sepolia finality is
///            ~13-19 min; Arc testnet has sub-second deterministic finality, so an Arc-sourced standard burn
///            attests in SECONDS. Sourcing from Arc makes the free tier fast.
///          - RELAYS RUN ON THE DESTINATIONS, NOT ARC. Arc's USDC is the NATIVE gas token: every USDC move
///            (the relay's mint included) routes through a node-level precompile (0x1800…) that forge's fork
///            SIMULATION (revm) does not implement — minting into Arc works ON-CHAIN, but forge always
///            simulates before broadcasting, so a relay is NEVER driven into Arc. Here the destinations
///            (Sepolia / Base Sepolia) do the minting: Sepolia calls Circle's
///            `MessageTransmitterV2.receiveMessage` DIRECTLY (no diamond lives there), while base-destined
///            messages from a UNIFIED-deployment hub ({CCTPHookDemo.hookDemoSetup}) are locked to its Base
///            diamond via `destinationCaller` and relay through {cctpDemoRelayVia} instead. The
///            mint recipient is the actor, a plain EOA on each destination. Separately, if the SIGNER's account
///            is EIP-7702-delegated (a smart-account/7702 setup on the actor — not an Arc default), the txpool
///            caps it at one in-flight tx, forcing `--slow`/sequential sends on the source-side deploy.
///
///         Each entrypoint drives only the existing adapter surface (`depositForBurn` + admin
///         `registerChainDomain` / `configureDomain`) or Circle's `receiveMessage`; no src/ contract is
///         modified. TESTNET-ONLY.
/// @dev RUNBOOK — <actor> = your keystore address (a plain EOA); FORGE_AUTH='--account <name>'
///  0. Fund via https://faucet.circle.com :
///       - Arc testnet USDC -> actor  (>= 1 USDC; on Arc, USDC is BOTH the bridged asset AND the gas token)
///       - Ethereum Sepolia ETH -> actor   (relay gas on the Sepolia destination)
///       - Base Sepolia ETH -> actor       (relay gas on the Base Sepolia destination)
///  1. Drive BOTH destinations end-to-end (setup -> burn -> Iris attest -> relay -> verify, unattended) with
///     ONE loop invocation (sepolia to DELIVERED, then base):
///       FORGE_AUTH='--account <name> --password-file <pw-file>' script/config/cctp-usdc-demo-loop.sh <actor>
///     (<pw-file> is a GITIGNORED file holding the KEYSTORE password — required for the unattended promise;
///      bare `--account <name>` works but prompts at every broadcast crank; see the loop's ENVIRONMENT header.)
///     Filter to a single destination with an optional 2nd arg (`sepolia` | `base`):
///       FORGE_AUTH='--account <name> --password-file <pw-file>' script/config/cctp-usdc-demo-loop.sh <actor> base
///     Attestation lands in SECONDS (Arc's instant finality) on the DEFAULT free standard tier.
///  2. Manual per-step equivalents (S=script/base/crosschain/CCTPUSDCDemo.s.sol:CCTPUSDCDemo, U=Arc USDC
///     0x3600…0000):
///     - setup:  forge script S --account <name> --broadcast --slow --verify --sig "cctpDemoSetup(uint256,uint32)" 0 2000
///     - status: forge script S --sender <actor> --sig "cctpDemoStatus(address,address,uint256,string,uint256,uint256)" \
///                 <hub> <actor> 1000000 sepolia 0 0            (broadcast-free)
///     - burn:   the Arc burn CANNOT pass forge's local simulation (revm lacks Arc's native-USDC precompile
///               0x1800…), so send it with `cast send` (the Arc node executes the precompile). First encode the
///               recipient (broadcast-free helper), then approve + depositForBurn:
///                 R=$(forge script S --sender <actor> --sig "cctpDemoRecipient(string,address)" sepolia <actor> \
///                       | sed -n 's/.*DEMO-RECIPIENT //p')
///                 cast send U    "approve(address,uint256)"    <hub> 1000000 --account <name> --rpc-url arc-testnet
///                 cast send <hub> "depositForBurn(uint256,bytes)" 1000000 "$R" --account <name> --rpc-url arc-testnet
///     - relay:  forge script S --account <name> --broadcast --slow --sig "cctpDemoRelay(string,bytes,bytes)" \
///                 sepolia <message> <attestation>              (on the DESTINATION)
///  3. Deploys auto-verify via Sourcify (Foundry's default verifier) — the setup command already includes
///     bare `--verify`; no API key needed (a chain Sourcify does not cover fails that one contract non-fatally).
///  Explorers: source (Arc) testnet.arcscan.app · dests sepolia.etherscan.io · sepolia.basescan.org
contract CCTPUSDCDemo is DeployCCTPBridgeAdapter {
    //*//////////////////////////////////////////////////////////////////////////
    //                        CCTP v2 TESTNET CONTRACTS (SAME ON EVERY TESTNET)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Circle CCTP v2 `TokenMessengerV2` — identical address on every testnet (Arc, Sepolia, Base).
    address internal constant TOKEN_MESSENGER_V2 = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;

    /// @notice Circle CCTP v2 `MessageTransmitterV2` — identical address on every testnet. Sepolia relays
    ///         call this DIRECTLY to mint; base relays go through the Base diamond's `relayMessage` when the
    ///         hub locked them to it (see {cctpDemoRelayVia}).
    address internal constant MESSAGE_TRANSMITTER_V2 = 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275;

    //*//////////////////////////////////////////////////////////////////////////
    //                          ARC SOURCE (THE HUB) CONSTANTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Foundry RPC alias for Circle's Arc testnet (foundry.toml interpolates ${ARC_TESTNET_RPC_URL}).
    string internal constant ARC_ALIAS = "arc-testnet";

    /// @notice Arc testnet chain id (the hub's home chain — the burn source of every destination).
    uint256 internal constant ARC_CHAIN_ID = 5_042_002;

    /// @notice Arc testnet CCTP domain (the Iris SOURCE domain used to fetch attestations for Arc-sourced burns).
    uint32 internal constant ARC_DOMAIN = 26;

    /// @notice USDC on Arc testnet — the NATIVE gas token, exposed as a 6-decimal ERC-20 view at this address
    ///         (which carries bytecode / is a proxy). `balanceOf(a) == a.balance / 1e12`; fund a fork with
    ///         `vm.deal(actor, amount * 1e12)` (ERC-20 `deal()` slot-hunting does not work on the native view).
    address internal constant ARC_USDC = 0x3600000000000000000000000000000000000000;

    //*//////////////////////////////////////////////////////////////////////////
    //                          DESTINATION USDC CONSTANTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice USDC on Ethereum Sepolia (CCTP domain 0, chain 11155111) — a normal ERC-20; relay gas is ETH.
    address internal constant SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    /// @notice USDC on Base Sepolia (CCTP domain 6, chain 84532) — a normal ERC-20; relay gas is ETH.
    address internal constant BASE_SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    //*//////////////////////////////////////////////////////////////////////////
    //                              DESTINATION PRESETS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A hardcoded Arc-hub destination. The source is ALWAYS Arc (`ARC_*`); a `Dest` describes one of
    ///         the two spokes the hub bridges to. `usdc` is the destination's normal ERC-20 (relay gas is ETH).
    struct Dest {
        string key; // loop / journal key: "sepolia" | "base"
        string rpcAlias; // foundry.toml RPC alias
        uint256 chainId; // destination chain id
        uint32 domain; // destination CCTP domain
        address usdc; // destination USDC (a normal ERC-20)
        string human; // human-readable name (logs)
        string explorer; // destination block explorer base
    }

    /// @notice Thrown when the destination key is neither `"sepolia"` nor `"base"`.
    error CCTPUSDCDemo__UnknownDest(string key);

    /// @notice Thrown when the actor's Arc USDC balance is below `amount` — the burn never pulls partially.
    error CCTPUSDCDemo__InsufficientUSDC(uint256 balance, uint256 required);

    /// @notice Thrown when Circle's `MessageTransmitterV2.receiveMessage` returns false on a destination relay.
    error CCTPUSDCDemo__RelayFailed();

    /// @notice Resolves the hardcoded destination preset for `key` (`"sepolia"` or `"base"`); reverts otherwise.
    function _dest(string memory key) internal pure returns (Dest memory dest) {
        bytes32 k = keccak256(bytes(key));
        if (k == keccak256("sepolia")) {
            dest = Dest({
                key: "sepolia",
                rpcAlias: "sepolia",
                chainId: 11_155_111,
                domain: 0,
                usdc: SEPOLIA_USDC,
                human: "Ethereum Sepolia",
                explorer: "https://sepolia.etherscan.io"
            });
        } else if (k == keccak256("base")) {
            dest = Dest({
                key: "base",
                rpcAlias: "base-sepolia",
                chainId: 84_532,
                domain: 6,
                usdc: BASE_SEPOLIA_USDC,
                human: "Base Sepolia",
                explorer: "https://sepolia.basescan.org"
            });
        } else {
            revert CCTPUSDCDemo__UnknownDest(key);
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          CRANK ENTRYPOINTS (BROADCAST)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice SETUP crank (ARC FORK ONLY, single-chain): assembles the ONE CCTP adapter diamond on Arc and
    ///         registers + configures BOTH destination domains (Sepolia 0 and Base Sepolia 6) with a
    ///         permissionless (`destinationCaller == bytes32(0)`) mint. `msg.sender` (the keystore signer) is
    ///         the admin. Prints `DEMO-SETUP <diamond>` — the loop reads the ONE hub address from this console
    ///         line (an Arc setup run's diamond is also in broadcast/.../5042002, but the console line is the
    ///         canonical source).
    /// @param maxFee               The per-domain CCTP `maxFee` (0 = free standard transfer).
    /// @param minFinalityThreshold The finality threshold (2000 standard-finalized, 1000 fast).
    function cctpDemoSetup(uint256 maxFee, uint32 minFinalityThreshold) external {
        address admin = msg.sender;

        vm.createSelectFork(ARC_ALIAS);
        vm.startBroadcast();
        address diamond = _setupHub(admin, maxFee, minFinalityThreshold);
        vm.stopBroadcast();

        console.log(string.concat("DEMO-SETUP ", vm.toString(diamond)));
    }

    /// @notice READ-ONLY status crank (broadcast-free — invoked WITHOUT `--broadcast`, a dry-run simulation):
    ///         forks Arc to read the actor's Arc USDC balance + the hub wiring, then forks THE ONE destination
    ///         `destKey` names to read the actor's destination USDC balance. Prints ONE line
    ///         `DEMO-STATUS <phase> <waitSeconds> <done> <srcBal> <dstBal>` the loop parses to decide
    ///         crank-vs-sleep. NON-VIEW because fork cheatcodes are non-view.
    /// @dev Post-burn the source balance drops, so the contract alone cannot tell NEEDS-FUNDS from a completed
    ///      burn — the loop carries `burned` (0/1) and `dstBaseline` (the destination balance at burn time) so
    ///      status can classify the delivery phase. Phase 0 NEEDS-SETUP verifies BOTH destination domains are
    ///      registered on the hub, so a half-configured hub is caught once whichever destination is driven.
    /// @param diamond     The Arc hub adapter diamond.
    /// @param actor       The address whose USDC balances are read (the keystore signer).
    /// @param amount      The burn amount (6-decimal USDC units).
    /// @param destKey     The destination preset key (`"sepolia"` or `"base"`).
    /// @param burned      0 before the burn is mined, 1 after (loop-carried).
    /// @param dstBaseline The destination USDC balance of `actor` recorded at burn time (loop-carried).
    function cctpDemoStatus(
        address diamond,
        address actor,
        uint256 amount,
        string calldata destKey,
        uint256 burned,
        uint256 dstBaseline
    ) external {
        Dest memory dest = _dest(destKey);
        (uint8 phase, uint256 waitSeconds, uint256 done, uint256 srcBal, uint256 dstBal) =
            _demoStatus(diamond, actor, amount, dest, burned, dstBaseline);
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

    /// @notice READ-ONLY encoding helper (broadcast-free AND fork-free): prints the ERC-7930 interoperable
    ///         address `DEMO-RECIPIENT <hex>` for `actor` on the destination `destKey` names — the exact bytes
    ///         {cctpDemoBurnStep} passes to `depositForBurn`. The loop reads this instead of reimplementing the
    ///         ERC-7930 format in shell, then submits the burn via `cast send` (see {cctpDemoBurn}). Invoke it
    ///         like the status read (with `--sender <actor>` so the repo `.env`'s `ETH_KEYSTORE_ACCOUNT` never
    ///         triggers an eager keystore unlock on this read-only call).
    function cctpDemoRecipient(string calldata destKey, address actor) external pure {
        Dest memory dest = _dest(destKey);
        console.log(
            string.concat("DEMO-RECIPIENT ", vm.toString(InteroperableAddress.formatEvmV1(dest.chainId, actor)))
        );
    }

    /// @notice BURN crank (ARC fork only): pulls exactly `amount` Arc USDC from `msg.sender` and burns it
    ///         through the hub toward `msg.sender` on the destination `destKey` names (recipient == the
    ///         signer, a plain EOA on the destination). Reverts {CCTPUSDCDemo__InsufficientUSDC} BEFORE any
    ///         approval if the signer's balance is short — never a partial pull. Prints
    ///         `DEMO-BURN <recipient> <amount>`.
    /// @dev On Arc this entrypoint CANNOT pass forge's local simulation: Arc's USDC is the native gas token and
    ///      every balance-move routes through a node-level precompile (0x1800…) that revm does not implement, so
    ///      the `transferFrom` inside `depositForBurn` reverts under any fork (and `forge script` executes the
    ///      broadcast body during collection, so the burn is never dispatched). The loop therefore drives the
    ///      Arc burn via `cast send` — which performs NO local simulation, letting the Arc NODE execute the
    ///      precompile natively. This wrapper is retained as the intended path if/when revm gains the precompile;
    ///      {cctpDemoBurnStep} remains the shared, broadcast-free burn used by the fork tests.
    function cctpDemoBurn(address diamond, uint256 amount, string calldata destKey) external {
        Dest memory dest = _dest(destKey);
        address actor = msg.sender;

        vm.createSelectFork(ARC_ALIAS);
        vm.startBroadcast();
        cctpDemoBurnStep(dest, diamond, actor, amount);
        vm.stopBroadcast();

        console.log(string.concat("DEMO-BURN ", vm.toString(actor), " ", vm.toString(amount)));
    }

    /// @notice RELAY crank (DESTINATION fork only): forwards the Iris-attested CCTP `message` + `attestation`
    ///         to Circle's `MessageTransmitterV2.receiveMessage` DIRECTLY on the destination, minting the
    ///         bridged USDC to the encoded recipient (the actor). Reverts {CCTPUSDCDemo__RelayFailed} if the
    ///         transmitter returns false. Prints `DEMO-RELAY <recipientBalanceAfter>`.
    function cctpDemoRelay(string calldata destKey, bytes calldata message, bytes calldata attestation) external {
        Dest memory dest = _dest(destKey);
        address actor = msg.sender;

        vm.createSelectFork(dest.rpcAlias);
        vm.startBroadcast();
        bool ok = IReceiverV2(MESSAGE_TRANSMITTER_V2).receiveMessage(message, attestation);
        vm.stopBroadcast();
        if (!ok) revert CCTPUSDCDemo__RelayFailed();

        console.log(string.concat("DEMO-RELAY ", vm.toString(IERC20(dest.usdc).balanceOf(actor))));
    }

    /// @notice RELAY crank variant for a DIAMOND-LOCKED destination: forwards the attested message through the
    ///         Lattice `diamond`'s permissionless `relayMessage` instead of Circle's transmitter directly.
    ///         Needed when the hub came from the unified demo setup ({CCTPHookDemo.hookDemoSetup} — `make
    ///         deploy-cctp`), which locks EVERY base-destined message to the Base diamond via
    ///         `destinationCaller` so hook messages cannot be consumed hook-lessly; plain transfers then relay
    ///         through the same diamond (a passthrough — the mint still goes to the encoded recipient). Prints
    ///         `DEMO-RELAY <recipientBalanceAfter>`.
    function cctpDemoRelayVia(
        address diamond,
        string calldata destKey,
        bytes calldata message,
        bytes calldata attestation
    ) external {
        Dest memory dest = _dest(destKey);
        address actor = msg.sender;

        vm.createSelectFork(dest.rpcAlias);
        vm.startBroadcast();
        ICCTPBridgeAdapter(diamond).relayMessage(message, attestation);
        vm.stopBroadcast();

        console.log(string.concat("DEMO-RELAY ", vm.toString(IERC20(dest.usdc).balanceOf(actor))));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     BROADCAST-FREE INTERNALS (SHARED WITH TESTS)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Assembles the ONE Arc hub diamond and registers + configures BOTH destination domains
    ///         (broadcast-free — {cctpDemoSetup} wraps this in `vm.startBroadcast()`; tests call it on a
    ///         selected Arc fork).
    /// @param admin       The address granted `DEFAULT_ADMIN_ROLE` (must be the caller of the register/config
    ///                     sub-calls — the broadcaster under `--broadcast`, or the probe in a test).
    /// @param maxFee      The per-domain CCTP `maxFee`.
    /// @param minFinality The per-domain CCTP `minFinalityThreshold`.
    /// @return diamond The assembled hub, both destination domains already registered + configured.
    function _setupHub(address admin, uint256 maxFee, uint32 minFinality) internal returns (address diamond) {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            buildCuts(admin, TOKEN_MESSENGER_V2, MESSAGE_TRANSMITTER_V2, ARC_USDC);
        diamond = _assemble(cuts, init, initCalldata);

        Dest memory sepolia = _dest("sepolia");
        Dest memory base = _dest("base");

        ICCTPBridgeAdapter(diamond).registerChainDomain(sepolia.chainId, sepolia.domain);
        ICCTPBridgeAdapter(diamond).configureDomain(sepolia.domain, maxFee, minFinality, bytes32(0));
        ICCTPBridgeAdapter(diamond).registerChainDomain(base.chainId, base.domain);
        ICCTPBridgeAdapter(diamond).configureDomain(base.domain, maxFee, minFinality, bytes32(0));
    }

    /// @notice One broadcast-free burn: balance-checks `actor` on Arc USDC, approves the hub for exactly
    ///         `amount`, and burns toward `actor` on `dest`'s chain (ERC-7930 recipient). Tests drive this
    ///         directly; the {cctpDemoBurn} wrapper drives it under broadcast with `actor == msg.sender`.
    function cctpDemoBurnStep(Dest memory dest, address diamond, address actor, uint256 amount) public {
        uint256 balance = IERC20(ARC_USDC).balanceOf(actor);
        if (balance < amount) revert CCTPUSDCDemo__InsufficientUSDC(balance, amount);

        IERC20(ARC_USDC).approve(diamond, amount);
        ICCTPBridgeAdapter(diamond).depositForBurn(amount, InteroperableAddress.formatEvmV1(dest.chainId, actor));
    }

    /// @notice The cross-fork status computation {cctpDemoStatus} prints, exposed so tests read the values
    ///         directly instead of parsing console output. Creates the Arc fork (LIVE tip) to read the hub
    ///         wiring + `actor`'s Arc USDC balance and the destination `maxFee`, then the destination fork to
    ///         read `actor`'s destination balance, then classifies the phase.
    /// @return phase       0 NEEDS-SETUP, 1 NEEDS-FUNDS, 2 READY-TO-BURN, 3 AWAITING-DELIVERY, 4 DELIVERED.
    /// @return waitSeconds A poll hint (30 while awaiting delivery, else 0 — actionable now).
    /// @return done        1 only when DELIVERED.
    /// @return srcBal      `actor`'s Arc USDC balance.
    /// @return dstBal      `actor`'s destination USDC balance.
    function _demoStatus(
        address diamond,
        address actor,
        uint256 amount,
        Dest memory dest,
        uint256 burned,
        uint256 dstBaseline
    ) internal returns (uint8 phase, uint256 waitSeconds, uint256 done, uint256 srcBal, uint256 dstBal) {
        // Arc source side: hub readiness (BOTH dests registered), actor's Arc USDC balance, dest maxFee ceiling.
        vm.createSelectFork(ARC_ALIAS);
        bool ready = _hubReady(diamond);
        srcBal = IERC20(ARC_USDC).balanceOf(actor);
        uint256 srcMaxFee = ready ? _domainMaxFee(diamond, dest.domain) : 0;

        // Destination side (LIVE tip): actor's destination USDC balance.
        vm.createSelectFork(dest.rpcAlias);
        dstBal = IERC20(dest.usdc).balanceOf(actor);

        // CCTP burns the full `amount` on the source and takes the fee (<= srcMaxFee) at mint time; the
        // recipient nets at least `amount - srcMaxFee`. Destination gas is ETH (never netted from dstBal).
        uint256 net = amount > srcMaxFee ? amount - srcMaxFee : 0;
        uint256 deliveredThreshold = dstBaseline + net;

        (phase, waitSeconds, done) = _computePhase(ready, amount, burned, srcBal, dstBal, deliveredThreshold);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              PHASE COMPUTATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Classifies the demo phase from hub readiness, the loop-carried burn flag, and balances.
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

    /// @notice True when `diamond` is a live CCTP hub whose `usdc()` is the Arc native USDC AND which has
    ///         registered BOTH destination chains (Sepolia and Base Sepolia). Guards against a codeless /
    ///         mismatched / half-configured hub — either destination missing reads as NEEDS-SETUP.
    function _hubReady(address diamond) internal view returns (bool) {
        if (diamond.code.length == 0) return false;
        try ICCTPBridgeAdapter(diamond).usdc() returns (address u) {
            if (u != ARC_USDC) return false;
        } catch {
            return false;
        }
        return _chainRegistered(diamond, _dest("sepolia").chainId) && _chainRegistered(diamond, _dest("base").chainId);
    }

    /// @dev True when `diamond` reports `chainId` as a registered CCTP chain (false on any read failure).
    function _chainRegistered(address diamond, uint256 chainId) internal view returns (bool) {
        try ICCTPBridgeAdapter(diamond).isChainRegistered(chainId) returns (bool registered) {
            return registered;
        } catch {
            return false;
        }
    }

    /// @dev The hub's `maxFee` for burns toward `domain` (the ceiling on the destination-side fee).
    function _domainMaxFee(address diamond, uint32 domain) internal view returns (uint256 maxFee) {
        (maxFee,,) = ICCTPBridgeAdapter(diamond).getDomainConfig(domain);
    }
}
