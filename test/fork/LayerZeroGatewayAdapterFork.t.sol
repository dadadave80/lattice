// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LayerZeroGatewayAdapterTestBase} from "@lattice-test/base/LayerZeroGatewayAdapterTestBase.sol";
import {LayerZeroGatewayAdapter} from "@lattice/crosschain/LayerZeroGatewayAdapter.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title LayerZeroGatewayAdapterFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Fork smoke test for the ERC-7786 message-gateway settlement family: the production LayerZero
///         gateway diamond (built from the {DeployLayerZeroGatewayAdapter} recipe) quotes and dispatches a
///         message through the LIVE LayerZero v2 EndpointV2 on Ethereum mainnet toward a Base (eid 30184)
///         recipient. The endpoint accepts sends from any OApp (no registration required); the default send
///         library for eid 30184 is configured on the live endpoint, so `quote` + `send` run the real
///         ULN/executor fee path end to end.
///
/// Enabling:
///   export MAINNET_RPC_URL=<your-rpc-url>
///   forge test --match-path "test/fork/LayerZeroGatewayAdapterFork.t.sol"
///
/// Without MAINNET_RPC_URL set, all tests here are skipped.
contract LayerZeroGatewayAdapterFork is LayerZeroGatewayAdapterTestBase {
    // LayerZero v2 EndpointV2 on Ethereum mainnet (verified, local eid 30101).
    address constant ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;

    uint256 constant BASE_CHAIN = 8453;
    uint32 constant BASE_EID = 30_184; // LayerZero v2 eid of Base
    uint128 constant DEST_GAS = 200_000;

    /// @notice Pinned mainnet block (2026-06-26; the eid-30184 default send library is set on the endpoint).
    uint256 constant FORK_BLOCK = 25_400_000;

    address admin = address(0xAD);
    address user = address(0x1234);
    address baseRecipient = address(0xCAFE);

    bytes recip; // ERC-7930 EVM recipient on Base
    bytes payload = hex"deadbeef";

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("mainnet", FORK_BLOCK);

        diamond = _deployLayerZeroGatewayAdapter(admin, ENDPOINT_V2);
        adapter = LayerZeroGatewayAdapter(diamond);

        recip = InteroperableAddress.formatEvmV1(BASE_CHAIN, baseRecipient);

        vm.startPrank(admin);
        adapter.registerEid(BASE_CHAIN, BASE_EID);
        // In production this is the Base-side adapter diamond; any non-zero 32-byte peer routes the packet.
        adapter.registerPeer(BASE_CHAIN, bytes32(uint256(uint160(diamond))));
        adapter.configureDestination(BASE_CHAIN, DEST_GAS, 0);
        vm.stopPrank();
    }

    /// @notice Happy path: quote the live native fee, send with exactly that fee, and get a real LayerZero
    ///         guid back with the ERC-7786 {MessageSent} event and no value stuck in the diamond.
    function test_Fork_SendMessageTowardBase() public {
        uint256 fee = adapter.quoteFee(recip, payload);
        assertGt(fee, 0, "live endpoint quotes a nonzero native fee");

        vm.deal(user, fee);
        vm.recordLogs();
        vm.prank(user);
        bytes32 guid = adapter.sendMessage{value: fee}(recip, payload, new bytes[](0));

        assertTrue(guid != bytes32(0), "endpoint minted a nonzero guid");

        // The diamond emitted MessageSent with the guid as the ERC-7786 sendId.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool seen;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == diamond && logs[i].topics[0] == IERC7786GatewaySource.MessageSent.selector
                    && logs[i].topics[1] == guid
            ) {
                seen = true;
                break;
            }
        }
        assertTrue(seen, "MessageSent(guid, ...) emitted by the diamond");

        assertEq(diamond.balance, 0, "no native value stuck in the diamond");
        assertEq(user.balance, 0, "exactly the quoted fee was consumed (no refund path)");
    }
}
