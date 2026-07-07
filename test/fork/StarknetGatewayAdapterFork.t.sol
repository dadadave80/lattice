// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StarknetGatewayAdapterTestBase} from "@lattice-test/base/StarknetGatewayAdapterTestBase.sol";
import {StarknetGatewayAdapter} from "@lattice/crosschain/StarknetGatewayAdapter.sol";
import {NonEvmAddress} from "@lattice/crosschain/libraries/NonEvmAddress.sol";

/// @dev Live-core pending-message getter the fork test needs that is NOT part of the deliberately minimal
///      vendored {IStarknetMessaging} subset (upstream: https://github.com/starkware-libs/cairo-lang). The
///      Starknet core marks a pending L1 -> L2 message as `l1ToL2Messages[msgHash] = fee + 1`.
interface IStarknetCorePendingMessages {
    function l1ToL2Messages(bytes32 msgHash) external view returns (uint256);
}

/// @title StarknetGatewayAdapterFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Fork smoke test for the L1 <-> L2 non-EVM connector settlement family: the production Starknet
///         gateway diamond (built from the {DeployStarknetGatewayAdapter} recipe) sends a fee-escrowed,
///         felt-chunk-encoded message through the LIVE Starknet core proxy on Ethereum mainnet toward a
///         registered `l1_handler` on `SN_MAIN`. The canonical observable asserted is the core's pending
///         marker `l1ToL2Messages(msgHash) == fee + 1`, plus the adapter's initiator record (the only party
///         allowed to cancel the in-flight message).
///
/// Enabling:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/StarknetGatewayAdapterFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests here are skipped.
contract StarknetGatewayAdapterFork is StarknetGatewayAdapterTestBase {
    // Starknet core on Ethereum mainnet (verified `Proxy` -> `Starknet` implementation).
    address constant STARKNET_CORE = 0xc662c410C0ECf747543f5bA90660f6ABeBD9C8c4;

    // CASA/CAIP-350 starknet chain reference: UTF-8 bytes of "SN_MAIN".
    bytes constant SN_MAIN = hex"534e5f4d41494e";

    // L2 target felt DELIBERATELY > 2**160 so 20-byte address-width bugs surface (full 32-byte felt).
    uint256 constant L2_TARGET = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d;

    // Non-refundable message fee escrowed by the core (its max per message is 1 ether — verified live).
    uint256 constant FEE = 0.001 ether;

    /// @notice Pinned mainnet block (2026-06-26).
    uint256 constant FORK_BLOCK = 25_400_000;

    address diamond;
    StarknetGatewayAdapter adapter;

    address admin = address(0xAD);
    address user = address(0x57A4);

    uint256 handlerSelector; // starknet_keccak("handle_deposit")
    bytes recip; // ERC-7930 starknet recipient toward L2_TARGET on SN_MAIN

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", FORK_BLOCK);

        diamond = _deployStarknetGatewayAdapter(admin, STARKNET_CORE, SN_MAIN);
        adapter = StarknetGatewayAdapter(diamond);

        handlerSelector = adapter.starknetSelector("handle_deposit");
        vm.prank(admin);
        adapter.registerL2Handler(L2_TARGET, handlerSelector);

        recip = NonEvmAddress.formatV1(NonEvmAddress.STARKNET_CHAIN_TYPE, SN_MAIN, bytes32(L2_TARGET));
    }

    /// @notice Happy path: escrow the fee in the live core, get a real (msgHash, nonce) back, and observe the
    ///         core's canonical `fee + 1` pending marker plus the adapter's initiator record.
    function test_Fork_SendMessageEscrowsFeeOnLiveCore() public {
        vm.deal(user, FEE);
        uint256 coreBalanceBefore = STARKNET_CORE.balance;

        vm.prank(user);
        (bytes32 msgHash, uint256 nonce) = adapter.sendMessage{value: FEE}(recip, hex"deadbeef");

        assertTrue(msgHash != bytes32(0), "core returned a message hash");
        assertGt(nonce, 0, "core-minted nonce (live counter is far past 0)");
        assertEq(
            IStarknetCorePendingMessages(STARKNET_CORE).l1ToL2Messages(msgHash),
            FEE + 1,
            "canonical pending marker: fee + 1"
        );
        assertEq(adapter.initiatorOf(msgHash), user, "the calling user is the recorded initiator");
        assertEq(STARKNET_CORE.balance - coreBalanceBefore, FEE, "fee escrowed by the core");
        assertEq(diamond.balance, 0, "no native value stuck in the diamond");
        assertEq(user.balance, 0, "the full fee left the user (never refunded by Starknet)");
    }
}
