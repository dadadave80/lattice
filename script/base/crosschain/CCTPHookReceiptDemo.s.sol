// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HOOK_MAGIC} from "@lattice/crosschain/circle/CCTPBridgeAdapterLib.sol";
import {CCTPHookReceipt} from "@lattice/examples/crosschain/CCTPHookReceipt.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Script, console} from "forge-std/Script.sol";

/// @title CCTPHookReceiptDemo
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Standalone Arc-to-Base CCTP v2 demo: Circle mints USDC directly to the recipient, then Lattice's
///         existing destination hook executor mints a fully on-chain receipt NFT to that same recipient.
/// @dev This script deploys no bridge stack. `receiptDemoSetup` deploys only the receipt against an existing
///      Base diamond's immutable executor. The live driver is script/config/cctp-hook-receipt-demo.sh.
contract CCTPHookReceiptDemo is Script {
    string internal constant BASE_ALIAS = "base-sepolia";
    uint256 internal constant BASE_CHAIN_ID = 84_532;
    address internal constant BASE_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    string internal constant ARC_ALIAS = "arc-testnet";
    address internal constant ARC_USDC = 0x3600000000000000000000000000000000000000;

    uint256 private constant MESSAGE_MIN_LENGTH = 400; // 376-byte v2 burn message + 24-byte Lattice envelope
    uint256 private constant SOURCE_DOMAIN_OFFSET = 4;
    uint256 private constant MINT_RECIPIENT_OFFSET = 184;
    uint256 private constant AMOUNT_OFFSET = 216;
    uint256 private constant SENDER_OFFSET = 248;
    uint256 private constant FEE_EXECUTED_OFFSET = 312;
    uint256 private constant HOOK_DATA_OFFSET = 376;

    error CCTPHookReceiptDemo__ZeroAddress();
    error CCTPHookReceiptDemo__InvalidMessage();
    error CCTPHookReceiptDemo__InvalidHook();
    error CCTPHookReceiptDemo__InvalidFee();

    /// @notice Deploy one receipt contract bound to `baseDiamond`'s existing hook executor.
    function receiptDemoSetup(address baseDiamond) external returns (address receipt, address executor) {
        if (baseDiamond == address(0)) revert CCTPHookReceiptDemo__ZeroAddress();
        vm.createSelectFork(BASE_ALIAS);
        executor = ICCTPBridgeAdapter(baseDiamond).hookExecutor();
        if (executor == address(0)) revert CCTPHookReceiptDemo__ZeroAddress();

        vm.startBroadcast();
        receipt = address(new CCTPHookReceipt(executor));
        vm.stopBroadcast();
        console.log(string.concat("DEMO-RECEIPT-SETUP ", vm.toString(receipt), " ", vm.toString(executor)));
    }

    /// @notice Print Base's ERC-7930 interoperable recipient bytes.
    function receiptDemoRecipient(address recipient) external pure {
        if (recipient == address(0)) revert CCTPHookReceiptDemo__ZeroAddress();
        console.log(
            string.concat(
                "DEMO-RECEIPT-RECIPIENT ", vm.toString(InteroperableAddress.formatEvmV1(BASE_CHAIN_ID, recipient))
            )
        );
    }

    /// @notice Print the payload-free Lattice envelope: HOOK_MAGIC || receipt.
    function receiptDemoEnvelope(address receipt) external pure {
        if (receipt == address(0)) revert CCTPHookReceiptDemo__ZeroAddress();
        console.log(
            string.concat("DEMO-RECEIPT-ENVELOPE ", vm.toString(abi.encodePacked(HOOK_MAGIC, bytes20(receipt))))
        );
    }

    /// @notice Relay one Iris-attested message through the destination diamond.
    function receiptDemoRelay(address baseDiamond, bytes calldata message, bytes calldata attestation) external {
        vm.createSelectFork(BASE_ALIAS);
        vm.startBroadcast();
        ICCTPBridgeAdapter(baseDiamond).relayMessageWithHook(message, attestation);
        vm.stopBroadcast();
        console.log("DEMO-RECEIPT-RELAY ok");
    }

    function receiptDemoArcBalance(address actor) external {
        vm.createSelectFork(ARC_ALIAS);
        console.log(string.concat("DEMO-RECEIPT-ARCBAL ", vm.toString(IERC20(ARC_USDC).balanceOf(actor))));
    }

    function receiptDemoBaseBalance(address recipient) external {
        vm.createSelectFork(BASE_ALIAS);
        console.log(string.concat("DEMO-RECEIPT-BASEBAL ", vm.toString(IERC20(BASE_USDC).balanceOf(recipient))));
    }

    function receiptDemoNftBalance(address receipt, address recipient) external {
        vm.createSelectFork(BASE_ALIAS);
        console.log(string.concat("DEMO-RECEIPT-NFTBAL ", vm.toString(CCTPHookReceipt(receipt).balanceOf(recipient))));
    }

    function receiptDemoData(address receipt, uint256 tokenId) external {
        vm.createSelectFork(BASE_ALIAS);
        CCTPHookReceipt.Receipt memory r = CCTPHookReceipt(receipt).receipt(tokenId);
        console.log(
            string.concat(
                "DEMO-RECEIPT-DATA ",
                vm.toString(tokenId),
                " ",
                vm.toString(r.sourceDomain),
                " ",
                vm.toString(r.sender),
                " ",
                vm.toString(r.originalRecipient),
                " ",
                vm.toString(r.amount),
                " ",
                vm.toString(r.recordedAt)
            )
        );
    }

    /// @notice Independently decode the attested facts and receipt target used for post-relay verification.
    function receiptDemoMessage(bytes calldata message)
        external
        pure
        returns (
            uint32 sourceDomain,
            bytes32 sender,
            address recipient,
            uint256 grossAmount,
            uint256 feeExecuted,
            uint256 netAmount,
            address target
        )
    {
        if (message.length < MESSAGE_MIN_LENGTH) revert CCTPHookReceiptDemo__InvalidMessage();

        bytes32 mintRecipient;
        bytes4 magic;
        assembly ("memory-safe") {
            sourceDomain := shr(224, calldataload(add(message.offset, SOURCE_DOMAIN_OFFSET)))
            mintRecipient := calldataload(add(message.offset, MINT_RECIPIENT_OFFSET))
            grossAmount := calldataload(add(message.offset, AMOUNT_OFFSET))
            sender := calldataload(add(message.offset, SENDER_OFFSET))
            feeExecuted := calldataload(add(message.offset, FEE_EXECUTED_OFFSET))
            magic := calldataload(add(message.offset, HOOK_DATA_OFFSET))
            target := shr(96, calldataload(add(message.offset, add(HOOK_DATA_OFFSET, 4))))
        }
        if (magic != HOOK_MAGIC || target == address(0)) revert CCTPHookReceiptDemo__InvalidHook();
        if (feeExecuted > grossAmount) revert CCTPHookReceiptDemo__InvalidFee();

        uint256 recipientWord = uint256(mintRecipient);
        if (recipientWord == 0 || recipientWord > type(uint160).max) {
            revert CCTPHookReceiptDemo__InvalidMessage();
        }
        recipient = address(uint160(recipientWord));
        netAmount = grossAmount - feeExecuted;
        console.log(
            string.concat(
                "DEMO-RECEIPT-MESSAGE ",
                vm.toString(sourceDomain),
                " ",
                vm.toString(sender),
                " ",
                vm.toString(recipient),
                " ",
                vm.toString(grossAmount),
                " ",
                vm.toString(feeExecuted),
                " ",
                vm.toString(netAmount),
                " ",
                vm.toString(target)
            )
        );
    }
}
