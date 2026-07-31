// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CCTPHookReceiptDemo} from "@lattice-script/base/crosschain/CCTPHookReceiptDemo.s.sol";
import {CCTPBridgeAdapterTestBase} from "@lattice-test/base/CCTPBridgeAdapterTestBase.sol";
import {HOOK_MAGIC} from "@lattice/crosschain/circle/CCTPBridgeAdapterLib.sol";
import {CCTPHookReceipt} from "@lattice/examples/crosschain/CCTPHookReceipt.sol";
import {CCTPHookReceiptRenderer} from "@lattice/examples/crosschain/libraries/CCTPHookReceiptRenderer.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {IReceiverV2} from "@lattice/interfaces/external/circle/IReceiverV2.sol";
import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";

contract ReceiptRendererHarness {
    function formatUSDC(uint256 amount) external pure returns (string memory) {
        return CCTPHookReceiptRenderer.formatUSDC(amount);
    }

    function sourceLabel(uint32 domain) external pure returns (string memory) {
        return CCTPHookReceiptRenderer.sourceLabel(domain);
    }

    function destinationLabel(uint256 chainId) external pure returns (string memory) {
        return CCTPHookReceiptRenderer.destinationLabel(chainId);
    }
}

contract ReceiptMessageTransmitter is IReceiverV2 {
    bool public result = true;
    uint256 public calls;

    function receiveMessage(bytes calldata, bytes calldata) external returns (bool) {
        ++calls;
        return result;
    }

    function localDomain() external pure returns (uint32) {
        return 6;
    }
}

contract NonERC721Receiver {}

/// @title CCTPHookReceiptTest
/// @notice Unit and real-diamond integration coverage for the CCTP delivery receipt.
contract CCTPHookReceiptTest is CCTPBridgeAdapterTestBase {
    address internal constant EXECUTOR = address(0xE0E0);
    address internal constant RECIPIENT = address(0xBEEF);
    address internal constant NEW_OWNER = address(0xCAFE);
    uint32 internal constant SOURCE_DOMAIN = 26;
    bytes32 internal constant SENDER = bytes32(uint256(uint160(address(0xA11CE))));
    uint256 internal constant AMOUNT = 1_000_000;

    CCTPHookReceipt internal receiptNft;
    ReceiptRendererHarness internal renderer;

    function setUp() public {
        receiptNft = new CCTPHookReceipt(EXECUTOR);
        renderer = new ReceiptRendererHarness();
    }

    function test_ConstructorRejectsZeroExecutor() public {
        vm.expectRevert(CCTPHookReceipt.CCTPHookReceipt__ZeroExecutor.selector);
        new CCTPHookReceipt(address(0));
    }

    function test_MetadataAndInterfaces() public view {
        assertEq(receiptNft.name(), "Lattice CCTP Receipt");
        assertEq(receiptNft.symbol(), "LCR");
        assertTrue(receiptNft.supportsInterface(0x80ac58cd), "ERC721");
        assertTrue(receiptNft.supportsInterface(0x5b5e139f), "ERC721Metadata");
        assertFalse(receiptNft.supportsInterface(0xffffffff), "invalid interface");
    }

    function test_OnCCTPHookRejectsNonExecutor() public {
        vm.expectRevert(CCTPHookReceipt.CCTPHookReceipt__NotExecutor.selector);
        receiptNft.onCCTPHook(SOURCE_DOMAIN, SENDER, _b32(RECIPIENT), AMOUNT, "");
    }

    function test_OnCCTPHookRejectsZeroRecipient() public {
        vm.prank(EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(CCTPHookReceipt.CCTPHookReceipt__InvalidRecipient.selector, bytes32(0)));
        receiptNft.onCCTPHook(SOURCE_DOMAIN, SENDER, bytes32(0), AMOUNT, "");
    }

    function test_OnCCTPHookRejectsNonEvmRecipientWord() public {
        bytes32 invalid = bytes32((uint256(1) << 200) | uint160(RECIPIENT));
        vm.prank(EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(CCTPHookReceipt.CCTPHookReceipt__InvalidRecipient.selector, invalid));
        receiptNft.onCCTPHook(SOURCE_DOMAIN, SENDER, invalid, AMOUNT, "");
    }

    function test_OnCCTPHookMintsAndStoresAttestedFacts() public {
        vm.warp(1_722_000_000);
        vm.expectEmit(true, true, true, true, address(receiptNft));
        emit CCTPHookReceipt.ReceiptMinted(1, RECIPIENT, SOURCE_DOMAIN, SENDER, AMOUNT, uint64(block.timestamp));

        vm.prank(EXECUTOR);
        receiptNft.onCCTPHook(SOURCE_DOMAIN, SENDER, _b32(RECIPIENT), AMOUNT, hex"deadbeef");

        assertEq(receiptNft.ownerOf(1), RECIPIENT);
        assertEq(receiptNft.balanceOf(RECIPIENT), 1);
        assertEq(receiptNft.nextTokenId(), 2);
        _assertReceipt(1, RECIPIENT, AMOUNT, uint64(block.timestamp));
    }

    function test_PayloadCannotChangeReceiptFacts() public {
        vm.prank(EXECUTOR);
        receiptNft.onCCTPHook(
            SOURCE_DOMAIN,
            SENDER,
            _b32(RECIPIENT),
            AMOUNT,
            abi.encode(address(0xDEAD), type(uint256).max, bytes32("hostile"))
        );
        _assertReceipt(1, RECIPIENT, AMOUNT, uint64(block.timestamp));
    }

    function test_RepeatedHooksMintSequentialReceipts() public {
        vm.startPrank(EXECUTOR);
        receiptNft.onCCTPHook(SOURCE_DOMAIN, SENDER, _b32(RECIPIENT), AMOUNT, "");
        receiptNft.onCCTPHook(SOURCE_DOMAIN, SENDER, _b32(RECIPIENT), AMOUNT + 1, "");
        vm.stopPrank();

        assertEq(receiptNft.ownerOf(1), RECIPIENT);
        assertEq(receiptNft.ownerOf(2), RECIPIENT);
        assertEq(receiptNft.balanceOf(RECIPIENT), 2);
        assertEq(receiptNft.nextTokenId(), 3);
    }

    function test_TransferDoesNotChangeOriginalRecipient() public {
        vm.prank(EXECUTOR);
        receiptNft.onCCTPHook(SOURCE_DOMAIN, SENDER, _b32(RECIPIENT), AMOUNT, "");

        vm.prank(RECIPIENT);
        receiptNft.transferFrom(RECIPIENT, NEW_OWNER, 1);

        assertEq(receiptNft.ownerOf(1), NEW_OWNER);
        CCTPHookReceipt.Receipt memory r = receiptNft.receipt(1);
        assertEq(r.originalRecipient, RECIPIENT);
    }

    function test_MintToContractWithoutReceiverSucceeds() public {
        NonERC721Receiver target = new NonERC721Receiver();
        vm.prank(EXECUTOR);
        receiptNft.onCCTPHook(SOURCE_DOMAIN, SENDER, _b32(address(target)), AMOUNT, "");
        assertEq(receiptNft.ownerOf(1), address(target));
    }

    function test_UnknownReceiptAndTokenUriRevert() public {
        bytes memory expected = abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, 99);
        vm.expectRevert(expected);
        receiptNft.receipt(99);
        vm.expectRevert(expected);
        receiptNft.tokenURI(99);
    }

    function test_TokenUriIsOnChainAndVariesByReceipt() public {
        vm.startPrank(EXECUTOR);
        receiptNft.onCCTPHook(SOURCE_DOMAIN, SENDER, _b32(RECIPIENT), AMOUNT, "");
        receiptNft.onCCTPHook(SOURCE_DOMAIN, SENDER, _b32(RECIPIENT), AMOUNT + 1, "");
        vm.stopPrank();

        string memory first = receiptNft.tokenURI(1);
        string memory second = receiptNft.tokenURI(2);
        assertTrue(_startsWith(first, "data:application/json;base64,"));
        assertTrue(keccak256(bytes(first)) != keccak256(bytes(second)));
    }

    function test_RendererFormatsUsdcAndLabels() public view {
        assertEq(renderer.formatUSDC(1), "0.000001");
        assertEq(renderer.formatUSDC(1_000_000), "1.000000");
        assertEq(renderer.formatUSDC(1_250_000), "1.250000");
        assertEq(renderer.sourceLabel(26), "ARC");
        assertEq(renderer.sourceLabel(99), "DOMAIN 99");
        assertEq(renderer.destinationLabel(84_532), "BASE SEPOLIA");
        assertEq(renderer.destinationLabel(99), "CHAIN 99");
    }

    function test_Integration_RealDiamondExecutorMintsToAttestedRecipient() public {
        address messenger = makeAddr("tokenMessenger");
        ReceiptMessageTransmitter transmitter = new ReceiptMessageTransmitter();
        address diamond = _deployCCTPBridgeAdapter(address(this), messenger, address(transmitter), makeAddr("usdc"));
        CCTPHookReceipt integrated = new CCTPHookReceipt(ICCTPBridgeAdapter(diamond).hookExecutor());

        bytes memory hookData = abi.encodePacked(HOOK_MAGIC, bytes20(address(integrated)));
        bytes memory message = _message(messenger, _b32(RECIPIENT), AMOUNT, hookData);
        ICCTPBridgeAdapter(diamond).relayMessageWithHook(message, hex"01");

        assertEq(transmitter.calls(), 1);
        assertEq(integrated.ownerOf(1), RECIPIENT, "mintRecipient owns the receipt");
        CCTPHookReceipt.Receipt memory r = integrated.receipt(1);
        assertEq(r.sourceDomain, SOURCE_DOMAIN);
        assertEq(r.sender, SENDER);
        assertEq(r.originalRecipient, RECIPIENT);
        assertEq(r.amount, AMOUNT);
    }

    function test_DemoMessageDecoderGroundedOnRealCircleFixture() public {
        string memory json = vm.readFile("test/fixtures/cctp/arc-to-base-hook-v2.json");
        bytes memory message = vm.parseJsonBytes(json, ".message");
        address expectedRecipient = vm.parseJsonAddress(json, ".vault");
        uint256 expectedAmount = vm.parseJsonUint(json, ".amount");

        CCTPHookReceiptDemo demo = new CCTPHookReceiptDemo();
        (
            uint32 sourceDomain,
            bytes32 sender,
            address recipient,
            uint256 grossAmount,
            uint256 feeExecuted,
            uint256 netAmount,
            address target
        ) = demo.receiptDemoMessage(message);

        assertEq(sourceDomain, SOURCE_DOMAIN);
        assertEq(sender, bytes32(uint256(uint160(0x6ca99B6179eAc891E3aCD4008b610fcE66F63E2d))));
        assertEq(recipient, expectedRecipient);
        assertEq(grossAmount, expectedAmount);
        assertEq(feeExecuted, 0);
        assertEq(netAmount, expectedAmount);
        assertEq(target, expectedRecipient);
    }

    function _assertReceipt(uint256 tokenId, address expectedRecipient, uint256 expectedAmount, uint64 expectedTime)
        internal
        view
    {
        CCTPHookReceipt.Receipt memory r = receiptNft.receipt(tokenId);
        assertEq(r.sourceDomain, SOURCE_DOMAIN);
        assertEq(r.sender, SENDER);
        assertEq(r.originalRecipient, expectedRecipient);
        assertEq(r.amount, expectedAmount);
        assertEq(r.recordedAt, expectedTime);
    }

    function _b32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    function _startsWith(string memory value, string memory prefix) internal pure returns (bool) {
        bytes memory a = bytes(value);
        bytes memory b = bytes(prefix);
        if (a.length < b.length) return false;
        for (uint256 i; i < b.length; ++i) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    function _message(address headerRecipient, bytes32 mintRecipient, uint256 amount, bytes memory hookData)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory header = abi.encodePacked(
            uint32(1),
            SOURCE_DOMAIN,
            uint32(6),
            bytes32(uint256(0x1234)),
            bytes32(0),
            bytes32(uint256(uint160(headerRecipient))),
            bytes32(0),
            uint32(2000),
            uint32(2000)
        );
        bytes memory body = abi.encodePacked(
            uint32(1), bytes32(0), mintRecipient, amount, SENDER, uint256(0), uint256(0), uint256(0), hookData
        );
        return abi.encodePacked(header, body);
    }
}
