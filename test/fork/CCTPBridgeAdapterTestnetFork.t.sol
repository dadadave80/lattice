// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CCTPBridgeAdapterTestBase} from "@lattice-test/base/CCTPBridgeAdapterTestBase.sol";
import {CCTPBridgeAdapter} from "@lattice/crosschain/CCTPBridgeAdapter.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @title CCTPBridgeAdapterTestnetFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Per-lane env-gated CCTP v2 TESTNET fork tests for the {DeployCCTPBridgeAdapter} recipe. Each test
///         `vm.skip`s cleanly when its lane's `*_RPC_URL` is unset (never fails), and pins a default block that
///         `*_FORK_BLOCK` overrides. CCTP v2 testnet addresses are the SAME on every testnet.
///
///         F4 (Sepolia)      : real testnet TokenMessengerV2 + USDC burn toward Base Sepolia — `totalSupply` drop.
///         F5 (Base Sepolia) : REAL captured (message, attestation) replay through `relayMessage` — the fixture
///                             recipient's USDC delta == amount - feeExecuted, and a second relay reverts
///                             (nonce consumed).
///         F6 (Base Sepolia) : the SAME real transfer through `relayMessageWithHook` reverts {CCTPInvalidHookData}
///                             (a standard transfer carries no Lattice hook envelope).
///         F7 (Arc)          : the recipe DEPLOYS on Circle Arc and wires + registers + configures (deploy proof).
///
/// Enabling (any subset):
///   export SEPOLIA_RPC_URL=<url>            # F4
///   export BASE_SEPOLIA_RPC_URL=<url>       # F5, F6
///   export ARC_TESTNET_RPC_URL=<url>        # F7
///   forge test --match-path "test/fork/CCTPBridgeAdapterTestnetFork.t.sol"
contract CCTPBridgeAdapterTestnetFork is CCTPBridgeAdapterTestBase {
    // CCTP v2 testnet contracts (identical on every testnet).
    address constant TOKEN_MESSENGER_V2 = 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA;
    address constant MESSAGE_TRANSMITTER_V2 = 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275;

    // Testnet USDC per lane.
    address constant USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // domain 0
    address constant USDC_BASE_SEPOLIA = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // domain 6
    address constant USDC_ARC = 0x3600000000000000000000000000000000000000; // domain 26 (chain 5042002)

    uint256 constant SEPOLIA_CHAIN = 11_155_111;
    uint256 constant BASE_SEPOLIA_CHAIN = 84_532;
    uint256 constant ARC_TESTNET_CHAIN = 5_042_002;
    uint32 constant SEPOLIA_DOMAIN = 0;
    uint32 constant BASE_SEPOLIA_DOMAIN = 6;
    uint32 constant ARC_DOMAIN = 26;

    // Pinned default fork blocks (overridable via the matching `*_FORK_BLOCK` env var).
    uint256 constant SEPOLIA_FORK_BLOCK = 11_275_095; // src of the captured F5 transfer
    uint256 constant BASE_SEPOLIA_FORK_BLOCK = 44_160_006; // receiveBlock (44_160_007) - 1 → nonce still unused
    uint256 constant ARC_FORK_BLOCK = 51_700_000; // recent Arc testnet block

    string constant FIXTURE = "test/fixtures/cctp/sepolia-to-base-sepolia-v2.json";

    address admin = address(0xAD);
    address user = address(0xCC79);
    address recipient = address(0xCAFE);

    function _skipUnless(string memory rpcVar) internal returns (bool ok) {
        if (bytes(vm.envOr(rpcVar, string(""))).length == 0) {
            vm.skip(true);
            return false;
        }
        return true;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        F4 — SEPOLIA BURN TOWARD BASE SEPOLIA
    //////////////////////////////////////////////////////////////////////////*//

    function test_Fork_Sepolia_BurnTowardBaseSepolia() public {
        if (!_skipUnless("SEPOLIA_RPC_URL")) return;
        vm.createSelectFork("sepolia", vm.envOr("SEPOLIA_FORK_BLOCK", SEPOLIA_FORK_BLOCK));

        address diamond = _deployCCTPBridgeAdapter(admin, TOKEN_MESSENGER_V2, MESSAGE_TRANSMITTER_V2, USDC_SEPOLIA);
        CCTPBridgeAdapter adapter = CCTPBridgeAdapter(diamond);

        vm.startPrank(admin);
        adapter.registerChainDomain(BASE_SEPOLIA_CHAIN, BASE_SEPOLIA_DOMAIN);
        adapter.configureDomain(BASE_SEPOLIA_DOMAIN, 500, 1000, bytes32(0)); // maxFee 500 < amount, fast finality
        vm.stopPrank();

        uint256 amount = 1_000e6;
        deal(USDC_SEPOLIA, user, amount);
        vm.prank(user);
        IERC20(USDC_SEPOLIA).approve(diamond, amount);

        uint256 supplyBefore = IERC20(USDC_SEPOLIA).totalSupply();

        vm.prank(user);
        adapter.depositForBurn(amount, InteroperableAddress.formatEvmV1(BASE_SEPOLIA_CHAIN, recipient));

        assertEq(IERC20(USDC_SEPOLIA).balanceOf(user), 0, "user debited exactly amount");
        assertEq(supplyBefore - IERC20(USDC_SEPOLIA).totalSupply(), amount, "testnet CCTP v2 burns the full amount");
        assertEq(IERC20(USDC_SEPOLIA).allowance(diamond, TOKEN_MESSENGER_V2), 0, "messenger allowance reset to 0");
        assertEq(IERC20(USDC_SEPOLIA).balanceOf(diamond), 0, "no USDC stuck in the diamond");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    F5 — BASE SEPOLIA REAL-ATTESTATION REPLAY
    //////////////////////////////////////////////////////////////////////////*//

    function test_Fork_BaseSepolia_RealAttestationReplay() public {
        if (!_skipUnless("BASE_SEPOLIA_RPC_URL")) return;
        (
            bytes memory message,
            bytes memory attestation,
            address fixtureRecipient,
            uint256 amount,
            uint256 feeExecuted
        ) = _loadFixture();
        if (message.length == 0) {
            vm.skip(true); // fixture not yet captured — see the file's TODO
            return;
        }
        vm.createSelectFork("base-sepolia", vm.envOr("BASE_SEPOLIA_FORK_BLOCK", BASE_SEPOLIA_FORK_BLOCK));

        address diamond = _deployCCTPBridgeAdapter(admin, TOKEN_MESSENGER_V2, MESSAGE_TRANSMITTER_V2, USDC_BASE_SEPOLIA);
        CCTPBridgeAdapter adapter = CCTPBridgeAdapter(diamond);

        uint256 balanceBefore = IERC20(USDC_BASE_SEPOLIA).balanceOf(fixtureRecipient);

        // Anyone may relay this permissionless (destinationCaller == 0) message; the real MessageTransmitterV2
        // validates the Iris attestation and mints DIRECTLY to the fixture recipient.
        vm.prank(user);
        adapter.relayMessage(message, attestation);

        assertEq(
            IERC20(USDC_BASE_SEPOLIA).balanceOf(fixtureRecipient) - balanceBefore,
            amount - feeExecuted,
            "recipient minted amount - feeExecuted"
        );

        // The nonce is now consumed — a second relay reverts (the transmitter rejects the used nonce).
        vm.prank(user);
        vm.expectRevert();
        adapter.relayMessage(message, attestation);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                F6 — REAL TRANSFER HAS NO LATTICE HOOK ENVELOPE
    //////////////////////////////////////////////////////////////////////////*//

    function test_Fork_BaseSepolia_RealTransferRejectedByHookRelay() public {
        if (!_skipUnless("BASE_SEPOLIA_RPC_URL")) return;
        (bytes memory message, bytes memory attestation, address fixtureRecipient,,) = _loadFixture();
        if (message.length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("base-sepolia", vm.envOr("BASE_SEPOLIA_FORK_BLOCK", BASE_SEPOLIA_FORK_BLOCK));

        address diamond = _deployCCTPBridgeAdapter(admin, TOKEN_MESSENGER_V2, MESSAGE_TRANSMITTER_V2, USDC_BASE_SEPOLIA);
        CCTPBridgeAdapter adapter = CCTPBridgeAdapter(diamond);

        uint256 balanceBefore = IERC20(USDC_BASE_SEPOLIA).balanceOf(fixtureRecipient);

        // A standard transfer carries no Lattice envelope → validation reverts BEFORE the mint.
        vm.prank(user);
        vm.expectRevert(ICCTPBridgeAdapter.CCTPInvalidHookData.selector);
        adapter.relayMessageWithHook(message, attestation);

        assertEq(
            IERC20(USDC_BASE_SEPOLIA).balanceOf(fixtureRecipient), balanceBefore, "no mint on a rejected hook relay"
        );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        F7 — ARC DEPLOY + WIRE PROOF
    //////////////////////////////////////////////////////////////////////////*//

    function test_Fork_Arc_DeployAndWire() public {
        if (!_skipUnless("ARC_TESTNET_RPC_URL")) return;
        vm.createSelectFork("arc-testnet", vm.envOr("ARC_TESTNET_FORK_BLOCK", ARC_FORK_BLOCK));

        // Proves the whole diamond recipe deploys on Circle Arc.
        address diamond = _deployCCTPBridgeAdapter(admin, TOKEN_MESSENGER_V2, MESSAGE_TRANSMITTER_V2, USDC_ARC);
        CCTPBridgeAdapter adapter = CCTPBridgeAdapter(diamond);

        vm.startPrank(admin);
        adapter.registerChainDomain(ARC_TESTNET_CHAIN, ARC_DOMAIN); // Arc is the local domain
        adapter.registerChainDomain(BASE_SEPOLIA_CHAIN, BASE_SEPOLIA_DOMAIN); // a destination
        adapter.configureDomain(BASE_SEPOLIA_DOMAIN, 500, 1000, bytes32(0));
        vm.stopPrank();

        assertEq(adapter.tokenMessenger(), TOKEN_MESSENGER_V2, "wired TokenMessengerV2");
        assertEq(adapter.messageTransmitter(), MESSAGE_TRANSMITTER_V2, "wired MessageTransmitterV2");
        assertEq(adapter.usdc(), USDC_ARC, "wired Arc USDC");
        assertTrue(adapter.hookExecutor() != address(0), "hook executor deployed on Arc");
        assertTrue(adapter.isChainRegistered(BASE_SEPOLIA_CHAIN), "Base Sepolia registered");
        assertEq(adapter.getDomain(ARC_TESTNET_CHAIN), ARC_DOMAIN, "Arc local domain registered");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              FIXTURE
    //////////////////////////////////////////////////////////////////////////*//

    function _loadFixture()
        internal
        view
        returns (bytes memory message, bytes memory attestation, address rcpt, uint256 amount, uint256 feeExecuted)
    {
        string memory json = vm.readFile(FIXTURE);
        message = vm.parseJsonBytes(json, ".message");
        attestation = vm.parseJsonBytes(json, ".attestation");
        rcpt = vm.parseJsonAddress(json, ".recipient");
        amount = vm.parseJsonUint(json, ".amount");
        feeExecuted = vm.parseJsonUint(json, ".feeExecuted");
    }
}
