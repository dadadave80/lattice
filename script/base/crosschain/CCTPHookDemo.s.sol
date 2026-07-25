// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployCCTPBridgeAdapter} from "@lattice-script/base/crosschain/DeployCCTPBridgeAdapter.s.sol";
import {HOOK_MAGIC} from "@lattice/crosschain/circle/CCTPBridgeAdapterLib.sol";
import {CCTPHookVault} from "@lattice/examples/crosschain/CCTPHookVault.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {console} from "forge-std/Script.sol";

/// @title CCTPHookDemo
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice LIVE showcase of Lattice's CCTP v2 HOOKS: programmable USDC that AUTO-CREDITS a named account on
///         arrival, in one attested cross-chain message. Arc testnet is the SOURCE; Base Sepolia is the
///         DESTINATION, where a Lattice CCTP diamond + a {CCTPHookVault} live. A burn from Arc via
///         `depositForBurnWithHook` carries the Lattice envelope `HOOK_MAGIC ‖ vault ‖ beneficiary`; relaying on
///         Base via the diamond's `relayMessageWithHook` MINTS USDC to the vault AND, in the same tx, has the
///         diamond's {CCTPHookExecutor} call `vault.onCCTPHook(...)`, which books the minted USDC to the
///         beneficiary and emits `Credited`. Unlike the plain Arc-hub demo (which mints via Circle's transmitter
///         directly), hooks are INBOUND, so the destination needs a Lattice diamond — that is what fires the
///         hook. Only the existing adapter surface is used; no src/ change beyond the standalone example vault.
///         TESTNET-ONLY.
/// @dev RUNBOOK — driven by script/config/cctp-hook-demo.sh; DEPLOYMENT IS SEPARATE FROM THE DEMO.
///     <actor> = your signer address. Auth either way, any OS: `make <target> KEYSTORE=<name>` (foundry
///     keystore — unattended on macOS via the Keychain, attended password prompts elsewhere) or
///     `make <target> PRIVATE_KEY=0x<testnet-key>` — both materialize FORGE_AUTH for the script.
///  0. Fund via https://faucet.circle.com : Arc testnet USDC -> actor (Arc's asset AND gas token; >= 1 USDC +
///     headroom) and Base Sepolia ETH -> actor (relay gas on the destination).
///  1. Demo (anyone; no deploy needed):  make demo-cctp-hook KEYSTORE=<name>|PRIVATE_KEY=0x<key>
///     (cast-send burn-with-hook on Arc -> Iris attest (seconds) -> relayMessageWithHook on Base -> verify the
///      vault credited the beneficiary). Optional args: <actor> <beneficiary>. Targets, in order: DEMO_* env
///      override -> .cctp-demo.deployment.env (your own stack) -> the canonical live deployment.
///  1b. Deploy your OWN stack first (optional, once):  make deploy-cctp KEYSTORE=<name>|PRIVATE_KEY=0x<key>
///      — runs {hookDemoSetup} on Arc+Base and persists the addresses. ONE deployment serves ALL the demos:
///      the hub is also registered for Ethereum Sepolia (the transfer demo adopts it), and the Base diamond
///      has Arc registered as a RETURN destination (the round trip burns back through it).
///  1c. Round trip (make demo-cctp-roundtrip, script/config/cctp-roundtrip-demo.sh): burn Arc -> Base (cast,
///      mint to the actor via {hookDemoRelayPlain}) then Base -> Arc ({hookDemoReturnBurn} under forge — Base
///      USDC is a normal ERC-20 — attested after Base's L1 finality, ~13-19 min free tier, then cast-send
///      `relayMessage` on the Arc hub: the Arc NODE executes the native-USDC mint revm cannot simulate).
///  2. Manual equivalents (S=script/base/crosschain/CCTPHookDemo.s.sol:CCTPHookDemo):
///     - setup:  ETHERSCAN_API_KEY= forge script S --account <name> --broadcast --verify --verifier sourcify --sig "hookDemoSetup(uint256,uint32)" 0 2000
///               (blank the key inline: a set ETHERSCAN_API_KEY makes forge pick Etherscan over the sourcify flag)
///     - burn:   the Arc burn CANNOT pass forge's local simulation (revm lacks Arc's native-USDC precompile
///               0x1800…) -> send it with cast. First encode the recipient + hook envelope (broadcast-free):
///                 R=$(forge script S --sender <actor> --sig "hookDemoRecipient(address)" <vault> | grep RECIPIENT)
///                 E=$(forge script S --sender <actor> --sig "hookDemoEnvelope(address,address)" <vault> <benef>)
///                 cast send 0x3600…0000 "approve(address,uint256)"          <arcHub> 1000000 --account <name> --rpc-url arc-testnet
///                 cast send <arcHub> "depositForBurnWithHook(uint256,bytes,bytes)" 1000000 "$R" "$E" --account <name> --rpc-url arc-testnet
///     - relay:  forge script S --account <name> --broadcast --sig "relayMessageWithHook…" via hookDemoRelay (on Base)
///     - verify: forge script S --sender <actor> --sig "hookDemoCredit(address,address)" <vault> <beneficiary>
///  Explorers: source (Arc) testnet.arcscan.app · dest base-sepolia.blockscout.com (reads the Sourcify verification)
contract CCTPHookDemo is DeployCCTPBridgeAdapter {
    /// @notice Circle CCTP v2 TokenMessengerV2 — identical address on every testnet.
    address internal constant TOKEN_MESSENGER_V2 = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;

    /// @notice Circle CCTP v2 MessageTransmitterV2 — identical address on every testnet.
    address internal constant MESSAGE_TRANSMITTER_V2 = 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275;

    /// @notice Arc testnet SOURCE: RPC alias, chain id, CCTP domain, native-gas USDC (6-dec ERC-20 view).
    string internal constant ARC_ALIAS = "arc-testnet";
    uint256 internal constant ARC_CHAIN_ID = 5_042_002;
    uint32 internal constant ARC_DOMAIN = 26;
    address internal constant ARC_USDC = 0x3600000000000000000000000000000000000000;

    /// @notice Base Sepolia DESTINATION: RPC alias, chain id, CCTP domain, USDC.
    string internal constant BASE_ALIAS = "base-sepolia";
    uint256 internal constant BASE_CHAIN_ID = 84_532;
    uint32 internal constant BASE_DOMAIN = 6;
    address internal constant BASE_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    /// @notice Ethereum Sepolia — the TRANSFER demo's second destination. The unified setup registers it on
    ///         the hub with a permissionless `destinationCaller` (plain transfers relay via Circle's
    ///         transmitter directly; Sepolia carries no diamond), so ONE deployment serves ALL the demos.
    uint256 internal constant SEPOLIA_CHAIN_ID = 11_155_111;
    uint32 internal constant SEPOLIA_DOMAIN = 0;

    //*//////////////////////////////////////////////////////////////////////////
    //                                 SETUP
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Deploy the ONE demo stack serving ALL the CCTP demos, in one multichain broadcast: the Arc source
    ///         hub (registered for Base Sepolia — hook-locked to the diamond — AND Ethereum Sepolia,
    ///         permissionless) plus the Base destination diamond + {CCTPHookVault}. Prints `DEMO-HOOK-SETUP
    ///         <arcHub> <baseDiamond> <vault>`. admin = msg.sender (the broadcaster), which is the
    ///         register/configure caller on Arc. The transfer demo (cctp-usdc-demo-loop.sh) adopts the hub and
    ///         relays base-destined transfers through the diamond's `relayMessage` (the hook lock applies to
    ///         every base-destined message this hub burns).
    function hookDemoSetup(uint256 maxFee, uint32 minFinalityThreshold) external {
        address admin = msg.sender;

        // Base destination FIRST: the diamond + auto-credit vault, with Arc registered ON the diamond for the
        // RETURN leg (Base -> Arc) — one deployment moves USDC in both directions. We need the diamond's
        // address to lock the outbound mint to it below.
        vm.createSelectFork(BASE_ALIAS);
        vm.startBroadcast();
        (address baseDiamond, address vault) = _setupHookDestWithReturn(admin, maxFee, minFinalityThreshold);
        vm.stopBroadcast();

        // Arc source hub: deploy + register Base, configuring its `destinationCaller` to the Base diamond so
        // ONLY that diamond's relayMessageWithHook can consume the message. Without this lock the mint is
        // permissionless and a third party could receiveMessage hook-lessly, stranding USDC in the vault with
        // no hook fired. (No USDC moves here, so it broadcasts fine on Arc despite revm's precompile gap.)
        vm.createSelectFork(ARC_ALIAS);
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            buildCuts(admin, TOKEN_MESSENGER_V2, MESSAGE_TRANSMITTER_V2, ARC_USDC);
        address arcHub = _assemble(cuts, init, cd);
        ICCTPBridgeAdapter(arcHub).registerChainDomain(BASE_CHAIN_ID, BASE_DOMAIN);
        ICCTPBridgeAdapter(arcHub)
            .configureDomain(BASE_DOMAIN, maxFee, minFinalityThreshold, bytes32(uint256(uint160(baseDiamond))));
        // Ethereum Sepolia for the TRANSFER demo: permissionless destinationCaller — no diamond lives there,
        // so plain transfers relay via Circle's transmitter directly.
        ICCTPBridgeAdapter(arcHub).registerChainDomain(SEPOLIA_CHAIN_ID, SEPOLIA_DOMAIN);
        ICCTPBridgeAdapter(arcHub).configureDomain(SEPOLIA_DOMAIN, maxFee, minFinalityThreshold, bytes32(0));
        vm.stopBroadcast();

        console.log(
            string.concat(
                "DEMO-HOOK-SETUP ", vm.toString(arcHub), " ", vm.toString(baseDiamond), " ", vm.toString(vault)
            )
        );
    }

    /// @notice Deploy the Base destination diamond + a {CCTPHookVault} bound to its {CCTPHookExecutor}
    ///         (broadcast-free — {hookDemoSetup} wraps this in `vm.startBroadcast()`; tests call it on a selected
    ///         Base fork). The vault's trust anchor is `diamond.hookExecutor()`.
    function _setupHookDest(address admin) public returns (address diamond, address vault) {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            buildCuts(admin, TOKEN_MESSENGER_V2, MESSAGE_TRANSMITTER_V2, BASE_USDC);
        diamond = _assemble(cuts, init, cd);
        address exec = ICCTPBridgeAdapter(diamond).hookExecutor();
        vault = address(new CCTPHookVault(exec, BASE_USDC));
    }

    /// @notice {_setupHookDest} plus the RETURN leg: registers Arc as a destination ON the Base diamond so the
    ///         same deployment also burns USDC Base -> Arc (`make demo-cctp-roundtrip`). The return domain is
    ///         configured PERMISSIONLESS (`destinationCaller == 0`) — no hook rides back toward Arc, so the
    ///         Arc-side mint may be relayed by anyone (the demo cast-sends it through the Arc hub's
    ///         `relayMessage`; revm cannot simulate Arc's native-USDC mint, so forge never drives it).
    /// @dev The register/configure sub-calls are admin-gated: under `vm.startBroadcast()` the caller is the
    ///      broadcaster (== `admin`); a test must pass the CALLING contract as `admin`.
    function _setupHookDestWithReturn(address admin, uint256 maxFee, uint32 minFinality)
        public
        returns (address diamond, address vault)
    {
        (diamond, vault) = _setupHookDest(admin);
        ICCTPBridgeAdapter(diamond).registerChainDomain(ARC_CHAIN_ID, ARC_DOMAIN);
        ICCTPBridgeAdapter(diamond).configureDomain(ARC_DOMAIN, maxFee, minFinality, bytes32(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       BROADCAST-FREE ENCODING HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Print `DEMO-HOOK-RECIPIENT <hex>` — the ERC-7930 recipient bytes for `recipient` on Base: the
    ///         VAULT for the hook showcase (CCTP must mint into the vault — its BACKING invariant), or the
    ///         ACTOR for the round trip's plain outbound transfer.
    function hookDemoRecipient(address recipient) external pure {
        console.log(
            string.concat(
                "DEMO-HOOK-RECIPIENT ", vm.toString(InteroperableAddress.formatEvmV1(BASE_CHAIN_ID, recipient))
            )
        );
    }

    /// @notice Print `DEMO-HOOK-ENVELOPE <hex>` — the Lattice hook envelope `HOOK_MAGIC ‖ vault ‖ beneficiary`
    ///         (4 + 20 + 20 = 44 bytes). `vault` is the hook target; `beneficiary` is the 20-byte payload.
    function hookDemoEnvelope(address vault, address beneficiary) external pure {
        console.log(
            string.concat(
                "DEMO-HOOK-ENVELOPE ", vm.toString(abi.encodePacked(HOOK_MAGIC, bytes20(vault), bytes20(beneficiary)))
            )
        );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              RELAY + VERIFY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Relay the attested message on Base via the destination diamond's `relayMessageWithHook` — mints
    ///         USDC to the vault AND fires the hook (executor -> vault.onCCTPHook -> credit) in one tx. Prints
    ///         `DEMO-HOOK-RELAY ok`. Base is a normal chain, so forge broadcasts this directly.
    function hookDemoRelay(address baseDiamond, bytes calldata message, bytes calldata attestation) external {
        vm.createSelectFork(BASE_ALIAS);
        vm.startBroadcast();
        ICCTPBridgeAdapter(baseDiamond).relayMessageWithHook(message, attestation);
        vm.stopBroadcast();
        console.log("DEMO-HOOK-RELAY ok");
    }

    /// @notice Read the vault credit on Base (broadcast-free; invoke with `--sender`). Prints
    ///         `DEMO-HOOK-CREDIT <creditOf(beneficiary)> <vaultUsdcBalance>`.
    function hookDemoCredit(address vault, address beneficiary) external {
        vm.createSelectFork(BASE_ALIAS);
        uint256 credit = CCTPHookVault(vault).creditOf(beneficiary);
        uint256 vaultBal = IERC20(BASE_USDC).balanceOf(vault);
        console.log(string.concat("DEMO-HOOK-CREDIT ", vm.toString(credit), " ", vm.toString(vaultBal)));
    }

    /// @notice Read `actor`'s Arc USDC balance (broadcast-free; invoke with `--sender`). Prints
    ///         `DEMO-HOOK-ARCBAL <balance>`. A fork READ of the native-USDC view is fine in revm — only
    ///         balance-MOVES route through Arc's node precompile (0x1800…); the view's `balanceOf` is plain
    ///         bytecode over the native balance (`balanceOf(a) == a.balance / 1e12`). Unlike `cast call`, this
    ///         needs no credentials: an `.env` `ETH_KEYSTORE_ACCOUNT` makes cast eagerly unlock that keystore
    ///         even for a read, prompting mid-run on /dev/tty.
    function hookDemoArcBalance(address actor) external {
        vm.createSelectFork(ARC_ALIAS);
        console.log(string.concat("DEMO-HOOK-ARCBAL ", vm.toString(IERC20(ARC_USDC).balanceOf(actor))));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      RETURN LEG (BASE -> ARC ROUND TRIP)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Thrown when the actor's Base USDC balance is below `amount` — the return burn never pulls
    ///         partially.
    error CCTPHookDemo__InsufficientBaseUSDC(uint256 balance, uint256 required);

    /// @notice Print `DEMO-HOOK-RETURN-READY 0|1` — whether `diamond` (on Base) has Arc registered as a
    ///         destination, i.e. whether this stack supports the round trip (broadcast-free; invoke with
    ///         `--sender`). Stacks deployed before the round-trip setup read 0 until their admin runs
    ///         `registerChainDomain(5042002, 26)` + `configureDomain(26, ...)` on the Base diamond.
    function hookDemoReturnReady(address diamond) external {
        vm.createSelectFork(BASE_ALIAS);
        bool ready;
        try ICCTPBridgeAdapter(diamond).isChainRegistered(ARC_CHAIN_ID) returns (bool r) {
            ready = r;
        } catch {}
        console.log(string.concat("DEMO-HOOK-RETURN-READY ", ready ? "1" : "0"));
    }

    /// @notice Read `actor`'s Base Sepolia USDC balance (broadcast-free; invoke with `--sender`). Prints
    ///         `DEMO-HOOK-BASEBAL <balance>` — the outbound leg's mint target and the return leg's fund check.
    function hookDemoBaseBalance(address actor) external {
        vm.createSelectFork(BASE_ALIAS);
        console.log(string.concat("DEMO-HOOK-BASEBAL ", vm.toString(IERC20(BASE_USDC).balanceOf(actor))));
    }

    /// @notice Relay an attested PLAIN (hook-less) message on Base through the destination diamond's
    ///         permissionless `relayMessage` — the outbound round-trip leg: the hub locks every base-destined
    ///         message to this diamond (`destinationCaller`), so even plain transfers relay through it; the
    ///         mint goes to the message's encoded recipient. Prints `DEMO-HOOK-RELAY-PLAIN ok`.
    function hookDemoRelayPlain(address baseDiamond, bytes calldata message, bytes calldata attestation) external {
        vm.createSelectFork(BASE_ALIAS);
        vm.startBroadcast();
        ICCTPBridgeAdapter(baseDiamond).relayMessage(message, attestation);
        vm.stopBroadcast();
        console.log("DEMO-HOOK-RELAY-PLAIN ok");
    }

    /// @notice RETURN-LEG burn (BASE fork, forge-broadcastable — Base USDC is a normal ERC-20, unlike Arc's
    ///         precompile-backed native USDC): burns `amount` Base USDC through the Base diamond toward
    ///         `msg.sender` on Arc. `--slow` recommended (approve + burn are two txs). Prints
    ///         `DEMO-HOOK-RETURN-BURN <actor> <amount>`.
    function hookDemoReturnBurn(address diamond, uint256 amount) external {
        address actor = msg.sender;
        vm.createSelectFork(BASE_ALIAS);
        vm.startBroadcast();
        returnBurnStep(diamond, actor, amount);
        vm.stopBroadcast();
        console.log(string.concat("DEMO-HOOK-RETURN-BURN ", vm.toString(actor), " ", vm.toString(amount)));
    }

    /// @notice One broadcast-free return burn: balance-checks `actor` on Base USDC, approves the diamond for
    ///         exactly `amount`, and burns toward `actor` on Arc (ERC-7930 recipient). Tests drive this
    ///         directly; {hookDemoReturnBurn} drives it under broadcast with `actor == msg.sender`.
    function returnBurnStep(address diamond, address actor, uint256 amount) public {
        uint256 balance = IERC20(BASE_USDC).balanceOf(actor);
        if (balance < amount) revert CCTPHookDemo__InsufficientBaseUSDC(balance, amount);

        IERC20(BASE_USDC).approve(diamond, amount);
        ICCTPBridgeAdapter(diamond).depositForBurn(amount, InteroperableAddress.formatEvmV1(ARC_CHAIN_ID, actor));
    }
}
