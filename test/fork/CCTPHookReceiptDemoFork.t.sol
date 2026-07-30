// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CCTPHookReceiptDemo} from "@lattice-script/base/crosschain/CCTPHookReceiptDemo.s.sol";
import {CCTPHookReceipt} from "@lattice/examples/crosschain/CCTPHookReceipt.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title CCTPHookReceiptDemoFork
/// @notice Env-gated Base Sepolia proof for receipt setup and real-attestation replay.
contract CCTPHookReceiptDemoFork is Test {
    string internal constant FIXTURE = "test/fixtures/cctp/arc-to-base-receipt-v2.json";
    uint256 internal constant BASE_SEPOLIA_FORK_BLOCK = 44_300_000;

    CCTPHookReceiptDemo internal demo;

    function setUp() public {
        if (bytes(vm.envOr("BASE_SEPOLIA_RPC_URL", string(""))).length == 0) return;
        demo = new CCTPHookReceiptDemo();
        vm.makePersistent(address(demo));
    }

    function _skipped() internal returns (bool skip) {
        if (bytes(vm.envOr("BASE_SEPOLIA_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            skip = true;
        }
    }

    function test_Fork_SetupBindsReceiptToDiamondExecutor() public {
        if (_skipped()) return;
        vm.createSelectFork("base-sepolia", vm.envOr("BASE_SEPOLIA_FORK_BLOCK", BASE_SEPOLIA_FORK_BLOCK));
        address diamond = 0x957259C5AEAa521c9DcFaEb6692C25ae53F349f1;

        (address receipt, address executor) = demo.receiptDemoSetup(diamond);

        assertEq(executor, ICCTPBridgeAdapter(diamond).hookExecutor());
        assertEq(CCTPHookReceipt(receipt).executor(), executor);
        assertEq(CCTPHookReceipt(receipt).name(), "Lattice CCTP Receipt");
    }

    function test_Fork_ReplayRealReceiptAttestation() public {
        if (_skipped()) return;
        string memory json = vm.readFile(FIXTURE);
        bytes memory message = vm.parseJsonBytes(json, ".message");
        if (message.length == 0) {
            vm.skip(true);
            return;
        }

        bytes memory attestation = vm.parseJsonBytes(json, ".attestation");
        address diamond = vm.parseJsonAddress(json, ".baseDiamond");
        address receipt = vm.parseJsonAddress(json, ".receipt");
        address recipient = vm.parseJsonAddress(json, ".recipient");
        uint256 amount = vm.parseJsonUint(json, ".amount");
        uint256 tokenId = vm.parseJsonUint(json, ".tokenId");
        uint256 receiveBlock = vm.parseJsonUint(json, ".receiveBlock");

        vm.createSelectFork("base-sepolia", receiveBlock - 1);
        ICCTPBridgeAdapter(diamond).relayMessageWithHook(message, attestation);

        assertEq(CCTPHookReceipt(receipt).ownerOf(tokenId), recipient);
        CCTPHookReceipt.Receipt memory r = CCTPHookReceipt(receipt).receipt(tokenId);
        assertEq(r.originalRecipient, recipient);
        assertEq(r.amount, amount);

        vm.expectRevert();
        ICCTPBridgeAdapter(diamond).relayMessageWithHook(message, attestation);
    }
}
