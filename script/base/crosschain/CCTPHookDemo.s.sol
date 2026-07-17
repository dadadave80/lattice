// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployCCTPBridgeAdapter} from "@lattice-script/base/crosschain/DeployCCTPBridgeAdapter.s.sol";
import {HOOK_MAGIC} from "@lattice/crosschain/libraries/CCTPBridgeAdapterLib.sol";
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
/// @dev RUNBOOK — driven end-to-end by script/config/cctp-hook-demo.sh. <actor> = your keystore address.
///  0. Fund via https://faucet.circle.com : Arc testnet USDC -> actor (Arc's asset AND gas token; >= 1 USDC +
///     headroom) and Base Sepolia ETH -> actor (relay gas on the destination).
///  1. Run:  FORGE_AUTH='--account <name> --password-file <pw>' script/config/cctp-hook-demo.sh
///     (setup on Arc+Base -> cast-send burn-with-hook on Arc -> Iris attest (seconds) -> relayMessageWithHook on
///      Base -> verify the vault credited the beneficiary). Optional args: <actor> <beneficiary>.
///  2. Manual equivalents (S=script/base/crosschain/CCTPHookDemo.s.sol:CCTPHookDemo):
///     - setup:  forge script S --account <name> --broadcast --verify --sig "hookDemoSetup(uint256,uint32)" 0 2000
///     - burn:   the Arc burn CANNOT pass forge's local simulation (revm lacks Arc's native-USDC precompile
///               0x1800…) -> send it with cast. First encode the recipient + hook envelope (broadcast-free):
///                 R=$(forge script S --sender <actor> --sig "hookDemoRecipient(address)" <vault> | grep RECIPIENT)
///                 E=$(forge script S --sender <actor> --sig "hookDemoEnvelope(address,address)" <vault> <benef>)
///                 cast send 0x3600…0000 "approve(address,uint256)"          <arcHub> 1000000 --account <name> --rpc-url arc-testnet
///                 cast send <arcHub> "depositForBurnWithHook(uint256,bytes,bytes)" 1000000 "$R" "$E" --account <name> --rpc-url arc-testnet
///     - relay:  forge script S --account <name> --broadcast --sig "relayMessageWithHook…" via hookDemoRelay (on Base)
///     - verify: forge script S --sender <actor> --sig "hookDemoCredit(address,address)" <vault> <beneficiary>
///  Explorers: source (Arc) testnet.arcscan.app · dest sepolia.basescan.org
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

    //*//////////////////////////////////////////////////////////////////////////
    //                                 SETUP
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Deploy the Arc source hub (with Base registered as a destination) AND the Base destination diamond
    ///         + {CCTPHookVault}, in one multichain broadcast. Prints `DEMO-HOOK-SETUP <arcHub> <baseDiamond>
    ///         <vault>`. admin = msg.sender (the broadcaster), which is the register/configure caller on Arc.
    function hookDemoSetup(uint256 maxFee, uint32 minFinalityThreshold) external {
        address admin = msg.sender;

        // Base destination FIRST (inbound relay only -> no domain registration): the diamond + auto-credit
        // vault. We need the diamond's address to lock the mint to it below.
        vm.createSelectFork(BASE_ALIAS);
        vm.startBroadcast();
        (address baseDiamond, address vault) = _setupHookDest(admin);
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

    //*//////////////////////////////////////////////////////////////////////////
    //                       BROADCAST-FREE ENCODING HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Print `DEMO-HOOK-RECIPIENT <hex>` — the ERC-7930 recipient for the burn: the vault on Base, so
    ///         CCTP mints the USDC into the vault (the vault's BACKING invariant requires this).
    function hookDemoRecipient(address vault) external pure {
        console.log(
            string.concat("DEMO-HOOK-RECIPIENT ", vm.toString(InteroperableAddress.formatEvmV1(BASE_CHAIN_ID, vault)))
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
}
