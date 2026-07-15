// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CCTPBridgeAdapterTestBase} from "@lattice-test/base/CCTPBridgeAdapterTestBase.sol";
import {CCTPBridgeAdapter} from "@lattice/crosschain/CCTPBridgeAdapter.sol";
import {HOOK_MAGIC} from "@lattice/crosschain/libraries/CCTPBridgeAdapterLib.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @title CCTPBridgeAdapterFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Fork smoke test for the burn-and-mint settlement family: the production CCTP adapter diamond
///         (built from the {DeployCCTPBridgeAdapter} recipe) burns LIVE USDC through Circle's CCTP v2
///         `TokenMessengerV2` on Ethereum mainnet toward a Base (domain 6) recipient. CCTP v2 burns the FULL
///         `amount` on the source chain (`_depositAndBurn`; the fee is taken at mint time on the destination),
///         so the on-chain observable asserted here is the USDC `totalSupply` decreasing by exactly `amount`.
///
/// Enabling:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/CCTPBridgeAdapterFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests here are skipped.
contract CCTPBridgeAdapterFork is CCTPBridgeAdapterTestBase {
    // Circle CCTP v2 on Ethereum mainnet (verified `AdminUpgradableProxy`s; impls `TokenMessengerV2` /
    // `MessageTransmitterV2`, deployed 2025-02-11).
    address constant TOKEN_MESSENGER_V2 = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;
    address constant MESSAGE_TRANSMITTER_V2 = 0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;
    // Circle USDC on Ethereum mainnet (verified `FiatTokenProxy` -> `FiatTokenV2_2`).
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 constant BASE_CHAIN = 8453;
    uint32 constant BASE_DOMAIN = 6; // CCTP domain id of Base
    uint256 constant MAX_FEE = 500; // 0.0005 USDC; TokenMessengerV2 requires maxFee < amount
    uint32 constant MIN_FINALITY = 2000; // standard (hard-finality) attestation
    uint256 constant AMOUNT = 1_000e6; // 1,000 USDC

    /// @notice Pinned mainnet block (2026-06-26, well after the CCTP v2 deployment).
    uint256 constant FORK_BLOCK = 25_400_000;

    address diamond;
    CCTPBridgeAdapter adapter;

    address admin = address(0xAD);
    address user = address(0xCC79);
    address baseRecipient = address(0xCAFE);

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", FORK_BLOCK);

        diamond = _deployCCTPBridgeAdapter(admin, TOKEN_MESSENGER_V2, MESSAGE_TRANSMITTER_V2, USDC);
        adapter = CCTPBridgeAdapter(diamond);

        vm.startPrank(admin);
        adapter.registerChainDomain(BASE_CHAIN, BASE_DOMAIN);
        adapter.configureDomain(BASE_DOMAIN, MAX_FEE, MIN_FINALITY, bytes32(0)); // permissionless mint
        vm.stopPrank();
    }

    /// @notice Happy path: pull exactly `AMOUNT` from the user, burn it through the live TokenMessengerV2
    ///         toward Base, and leave no allowance or balance behind on the diamond.
    function test_Fork_DepositForBurnTowardBase() public {
        deal(USDC, user, AMOUNT);
        vm.prank(user);
        IERC20(USDC).approve(diamond, AMOUNT);

        uint256 supplyBefore = IERC20(USDC).totalSupply();

        vm.prank(user);
        adapter.depositForBurn(AMOUNT, InteroperableAddress.formatEvmV1(BASE_CHAIN, baseRecipient));

        assertEq(IERC20(USDC).balanceOf(user), 0, "user debited exactly amount");
        assertEq(supplyBefore - IERC20(USDC).totalSupply(), AMOUNT, "CCTP v2 burns the full amount on source");
        assertEq(IERC20(USDC).allowance(diamond, TOKEN_MESSENGER_V2), 0, "messenger allowance reset to 0");
        assertEq(IERC20(USDC).balanceOf(diamond), 0, "no USDC stuck in the diamond");
    }

    /// @notice F2 — the live TokenMessengerV2 accepts a Lattice hook envelope via `depositForBurnWithHook`: the
    ///         FULL `amount` is burned on source (the hook is destination-executed, not here), the allowance is
    ///         reset, and nothing is stranded on the diamond.
    function test_Fork_DepositForBurnWithHookTowardBase() public {
        deal(USDC, user, AMOUNT);
        vm.prank(user);
        IERC20(USDC).approve(diamond, AMOUNT);

        // A Lattice envelope: HOOK_MAGIC ‖ target(20) ‖ payload. Target is a stand-in Base recipient.
        bytes memory hookData = abi.encodePacked(HOOK_MAGIC, bytes20(baseRecipient), bytes("settle"));

        uint256 supplyBefore = IERC20(USDC).totalSupply();

        vm.prank(user);
        adapter.depositForBurnWithHook(AMOUNT, InteroperableAddress.formatEvmV1(BASE_CHAIN, baseRecipient), hookData);

        assertEq(IERC20(USDC).balanceOf(user), 0, "user debited exactly amount");
        assertEq(supplyBefore - IERC20(USDC).totalSupply(), AMOUNT, "CCTP v2 burns the full amount on source");
        assertEq(IERC20(USDC).allowance(diamond, TOKEN_MESSENGER_V2), 0, "messenger allowance reset to 0");
        assertEq(IERC20(USDC).balanceOf(diamond), 0, "no USDC stuck in the diamond");
    }

    /// @notice F3 — empirical closure: an UNCONFIGURED domain (registered but never `configureDomain`d, so
    ///         `maxFee == 0` / `minFinalityThreshold == 0` / `destinationCaller == 0`) maps to CCTP's free
    ///         permissionless standard transfer and the live TokenMessengerV2 ACCEPTS the burn. This is why the
    ///         adapter deliberately adds NO unconfigured-domain guard. If this ever reverts on-chain, add
    ///         `CCTPDomainNotConfigured` + tests and gate the burn on it.
    function test_Fork_DepositForBurnUnconfiguredDomainSucceeds() public {
        uint256 avaxChain = 43_114;
        uint32 avaxDomain = 1; // Avalanche C-Chain CCTP domain
        vm.prank(admin);
        adapter.registerChainDomain(avaxChain, avaxDomain); // registered but NOT configured (zero config)

        deal(USDC, user, AMOUNT);
        vm.prank(user);
        IERC20(USDC).approve(diamond, AMOUNT);

        uint256 supplyBefore = IERC20(USDC).totalSupply();

        vm.prank(user);
        adapter.depositForBurn(AMOUNT, InteroperableAddress.formatEvmV1(avaxChain, baseRecipient));

        assertEq(supplyBefore - IERC20(USDC).totalSupply(), AMOUNT, "unconfigured domain burns the full amount");
        assertEq(IERC20(USDC).allowance(diamond, TOKEN_MESSENGER_V2), 0, "messenger allowance reset to 0");
        assertEq(IERC20(USDC).balanceOf(diamond), 0, "no USDC stuck in the diamond");
    }
}
