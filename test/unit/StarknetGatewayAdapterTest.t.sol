// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {StarknetGatewayAdapterTestBase} from "@lattice-test/base/StarknetGatewayAdapterTestBase.sol";
import {MockStarknetMessaging} from "@lattice-test/mocks/MockStarknetMessaging.sol";
import {NonEvmAddress} from "@lattice/crosschain/libraries/NonEvmAddress.sol";
import {StarknetGatewayAdapterLib} from "@lattice/crosschain/libraries/StarknetGatewayAdapterLib.sol";
import {StarknetGatewayAdapter} from "@lattice/crosschain/starknet/StarknetGatewayAdapter.sol";
import {IStarknetGatewayAdapter} from "@lattice/interfaces/crosschain/IStarknetGatewayAdapter.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @notice External harness so the internal felt-chunk codec is exercised through an external call frame
///         (for `vm.expectRevert` + fuzzing) exactly as a consumer would call it.
contract StarknetFeltCodecHarness {
    function encode(bytes memory payload) external pure returns (uint256[] memory) {
        return StarknetGatewayAdapterLib.encodeFelts(payload);
    }

    function decode(uint256[] memory felts) external pure returns (bytes memory) {
        return StarknetGatewayAdapterLib.decodeFelts(felts);
    }
}

contract StarknetGatewayAdapterTest is StarknetGatewayAdapterTestBase {
    MockStarknetMessaging core;
    StarknetFeltCodecHarness codec;

    address diamond;
    StarknetGatewayAdapter adapter;

    address admin = address(0x1);
    address user = address(0x2);
    address keeper = address(0x3);
    address other = address(0x4);

    // CASA/CAIP-350 starknet chain references: UTF-8 bytes of the chain-id string.
    bytes constant SN_MAIN = hex"534e5f4d41494e"; // "SN_MAIN"
    bytes constant SN_GOERLI = hex"534e5f474f45524c49"; // "SN_GOERLI"

    // L2 target felt DELIBERATELY > 2**160 so 20-byte address-width bugs surface (full 32-byte felt).
    uint256 constant L2_TARGET = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d;
    // Trusted L2 sender felt for the inbound consume path (also > 2**160).
    uint256 constant L2_FROM = 0x06b648f6a9d15a25a7dd6b96e927e0c4a4d1e0dbdf1b06e04a8dc7e2f9c1b7aa;

    uint256 constant FEE = 0.1 ether;

    uint256 handlerSelector; // starknet_keccak("handle_deposit"), computed inline in setUp
    bytes recip; // ERC-7930 starknet recipient toward L2_TARGET on SN_MAIN

    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    // 40-byte payload for the hand-built chunking expectation (bytes 0x00..0x27).
    bytes constant PAYLOAD_40 = hex"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f2021222324252627";
    // Hand-built expectation (independent of the lib encoder): felts[0] = 40 (byte count);
    // felts[1] = payload bytes [0..31) as a 31-byte big-endian integer;
    // felts[2] = payload bytes [31..40) (9 bytes) right-padded with 22 zero bytes to the 31-byte frame.
    uint256 constant CHUNK_0 = 0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e;
    uint256 constant CHUNK_1 = 0x1f202122232425262700000000000000000000000000000000000000000000;

    function setUp() public {
        core = new MockStarknetMessaging();
        codec = new StarknetFeltCodecHarness();

        diamond = _deployStarknetGatewayAdapter(admin, address(core), SN_MAIN);
        adapter = StarknetGatewayAdapter(diamond);

        // starknet_keccak of the l1_handler name, mask arithmetic computed here (not via the helper under test).
        handlerSelector = uint256(keccak256(bytes("handle_deposit"))) & ((uint256(1) << 250) - 1);
        recip = NonEvmAddress.formatV1(NonEvmAddress.STARKNET_CHAIN_TYPE, SN_MAIN, bytes32(L2_TARGET));

        vm.startPrank(admin);
        adapter.registerL2Handler(L2_TARGET, handlerSelector);
        adapter.setTrustedL2Sender(L2_FROM, true);
        vm.stopPrank();

        vm.deal(user, 10 ether);
    }

    /// @dev The hand-built expected felt array for {PAYLOAD_40}.
    function _expectedFelts40() internal pure returns (uint256[] memory felts) {
        felts = new uint256[](3);
        felts[0] = 40;
        felts[1] = CHUNK_0;
        felts[2] = CHUNK_1;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   INIT
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitWiresCoreAndChainReference() public view {
        assertEq(adapter.starknetCore(), address(core));
        assertEq(adapter.expectedChainReference(), SN_MAIN);
    }

    /// @dev Only `d.initialize` is wrapped in `expectRevert` (the init revert bubbles up through
    ///      {Diamond.initialize}); `deployer` was created in `setUp`.
    function _expectInitRevert(address core_, bytes memory chainRef, bytes4 err) internal {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, core_, chainRef);
        Diamond d = new Diamond();
        vm.expectRevert(err);
        d.initialize(cuts, init, initCalldata);
    }

    function test_InitRejectsZeroCore() public {
        _expectInitRevert(address(0), SN_MAIN, IStarknetGatewayAdapter.StarknetZeroAddress.selector);
    }

    function test_InitRejectsEmptyChainReference() public {
        _expectInitRevert(address(core), hex"", IStarknetGatewayAdapter.StarknetEmptyChainReference.selector);
    }

    function test_SupportsInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IStarknetGatewayAdapter).interfaceId));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterL2Handler() public {
        uint256 target = 0x05aa;
        vm.expectEmit(true, false, false, true, diamond);
        emit IStarknetGatewayAdapter.RegisteredL2Handler(target, handlerSelector);
        vm.prank(admin);
        adapter.registerL2Handler(target, handlerSelector);
        assertEq(adapter.l1HandlerSelector(target), handlerSelector);
        assertEq(adapter.l1HandlerSelector(0x05ab), 0, "unregistered target stays zero");
    }

    function test_RegisterL2HandlerRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerL2Handler(L2_TARGET, handlerSelector);
    }

    function test_RegisterL2HandlerRevertsOnNonFeltValues() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IStarknetGatewayAdapter.StarknetNotAFelt.selector, 0));
        adapter.registerL2Handler(0, handlerSelector);
        vm.expectRevert(
            abi.encodeWithSelector(IStarknetGatewayAdapter.StarknetNotAFelt.selector, NonEvmAddress.FIELD_PRIME)
        );
        adapter.registerL2Handler(NonEvmAddress.FIELD_PRIME, handlerSelector);
        vm.expectRevert(abi.encodeWithSelector(IStarknetGatewayAdapter.StarknetNotAFelt.selector, 0));
        adapter.registerL2Handler(L2_TARGET, 0);
        vm.expectRevert(
            abi.encodeWithSelector(IStarknetGatewayAdapter.StarknetNotAFelt.selector, NonEvmAddress.FIELD_PRIME)
        );
        adapter.registerL2Handler(L2_TARGET, NonEvmAddress.FIELD_PRIME);
        vm.stopPrank();
    }

    function test_SetTrustedL2Sender() public {
        assertTrue(adapter.isTrustedL2Sender(L2_FROM));
        vm.expectEmit(true, false, false, true, diamond);
        emit IStarknetGatewayAdapter.SetTrustedL2Sender(L2_FROM, false);
        vm.prank(admin);
        adapter.setTrustedL2Sender(L2_FROM, false);
        assertFalse(adapter.isTrustedL2Sender(L2_FROM));
    }

    function test_SetTrustedL2SenderRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.setTrustedL2Sender(L2_FROM, false);
    }

    function test_SetTrustedL2SenderRevertsOnNonFeltValues() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IStarknetGatewayAdapter.StarknetNotAFelt.selector, 0));
        adapter.setTrustedL2Sender(0, true);
        vm.expectRevert(
            abi.encodeWithSelector(IStarknetGatewayAdapter.StarknetNotAFelt.selector, NonEvmAddress.FIELD_PRIME)
        );
        adapter.setTrustedL2Sender(NonEvmAddress.FIELD_PRIME, true);
        vm.stopPrank();
    }

    /// @notice starknetSelector == keccak256 masked to the low 250 bits (independently recomputed here).
    function test_StarknetSelectorVector() public view {
        uint256 expected = uint256(keccak256(bytes("handle_deposit")));
        expected &= (uint256(1) << 250) - 1;
        assertEq(adapter.starknetSelector("handle_deposit"), expected);
        assertLt(adapter.starknetSelector("handle_deposit"), NonEvmAddress.FIELD_PRIME, "selector is a felt");
        // Distinct names hash to distinct selectors (sanity on the masking, not a collision proof).
        assertTrue(adapter.starknetSelector("handle_deposit") != adapter.starknetSelector("handle_withdraw"));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    function test_SendMessageHappyPath() public {
        uint256[] memory expected = _expectedFelts40();
        bytes32 expectedHash = core.l1ToL2MsgHash(diamond, L2_TARGET, handlerSelector, expected, 0);

        vm.prank(user);
        (bytes32 msgHash, uint256 nonce) = adapter.sendMessage{value: FEE}(recip, PAYLOAD_40);

        // Felts recorded verbatim by the core: length prefix + 31-byte chunking (hand-built expectation).
        assertEq(core.lastPayload(), expected, "felt-chunk wire format");
        // The recipient felt is the FULL 32-byte value (L2_TARGET > 2**160 — no address-width truncation).
        assertEq(core.lastToAddress(), L2_TARGET, "full felt252 recipient");
        assertEq(core.lastSelector(), handlerSelector, "registered l1_handler selector");
        assertEq(core.lastSender(), diamond, "the DIAMOND is the L1 sender on the core");
        assertEq(core.lastFee(), FEE, "fee forwarded");
        assertEq(address(core).balance, FEE, "fee escrowed in the core");
        assertEq(core.sendCalls(), 1);
        // Returned hash/nonce + the initiator record used by cancellation.
        assertEq(msgHash, expectedHash);
        assertEq(nonce, 0, "first core-minted nonce");
        assertEq(adapter.initiatorOf(msgHash), user, "initiator recorded");
    }

    function test_SendMessageEmitsEvent() public {
        bytes32 expectedHash = core.l1ToL2MsgHash(diamond, L2_TARGET, handlerSelector, _expectedFelts40(), 0);
        vm.expectEmit(true, true, false, true, diamond);
        emit IStarknetGatewayAdapter.StarknetMessageSent(
            user, L2_TARGET, handlerSelector, expectedHash, 0, FEE, PAYLOAD_40
        );
        vm.prank(user);
        adapter.sendMessage{value: FEE}(recip, PAYLOAD_40);
    }

    function test_SendMessageRevertsZeroFee() public {
        vm.prank(user);
        vm.expectRevert(IStarknetGatewayAdapter.StarknetZeroFee.selector);
        adapter.sendMessage(recip, PAYLOAD_40);
    }

    /// @notice The fee upper bound is the core's — a > 1 ether fee bubbles the core's max-fee revert.
    function test_SendMessageFeeAboveMaxBubblesCoreRevert() public {
        vm.deal(user, 2 ether);
        vm.prank(user);
        vm.expectRevert(bytes("MAX_L1_MSG_FEE_EXCEEDED"));
        adapter.sendMessage{value: 1 ether + 1}(recip, PAYLOAD_40);
    }

    function test_SendMessageRevertsWrongChainType() public {
        bytes memory evmRecipient = InteroperableAddress.formatEvmV1(1, address(0xBEEF));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IStarknetGatewayAdapter.StarknetWrongChainType.selector, bytes2(0x0000)));
        adapter.sendMessage{value: FEE}(evmRecipient, PAYLOAD_40);
    }

    function test_SendMessageRevertsChainReferenceMismatch() public {
        bytes memory goerliRecipient =
            NonEvmAddress.formatV1(NonEvmAddress.STARKNET_CHAIN_TYPE, SN_GOERLI, bytes32(L2_TARGET));
        vm.prank(user);
        vm.expectRevert(IStarknetGatewayAdapter.StarknetChainReferenceMismatch.selector);
        adapter.sendMessage{value: FEE}(goerliRecipient, PAYLOAD_40);
    }

    function test_SendMessageRevertsUnregisteredTarget() public {
        uint256 unregistered = L2_TARGET - 1;
        bytes memory unknownRecipient =
            NonEvmAddress.formatV1(NonEvmAddress.STARKNET_CHAIN_TYPE, SN_MAIN, bytes32(unregistered));
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IStarknetGatewayAdapter.StarknetTargetNotRegistered.selector, unregistered)
        );
        adapter.sendMessage{value: FEE}(unknownRecipient, PAYLOAD_40);
    }

    function test_SendMessageRevertsNonFeltRecipient() public {
        bytes memory nonFelt =
            NonEvmAddress.formatV1(NonEvmAddress.STARKNET_CHAIN_TYPE, SN_MAIN, bytes32(NonEvmAddress.FIELD_PRIME));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(NonEvmAddress.NonEvmAddressNotAFelt.selector, NonEvmAddress.FIELD_PRIME));
        adapter.sendMessage{value: FEE}(nonFelt, PAYLOAD_40);
    }

    /// @notice FIELD_PRIME - 1 is a valid felt (the boundary passes the range check and reaches the target
    ///         registry, proving the range check is strict-less-than).
    function test_SendMessageAcceptsFieldPrimeMinusOne() public {
        uint256 boundary = NonEvmAddress.FIELD_PRIME - 1;
        vm.prank(admin);
        adapter.registerL2Handler(boundary, handlerSelector);
        bytes memory boundaryRecipient =
            NonEvmAddress.formatV1(NonEvmAddress.STARKNET_CHAIN_TYPE, SN_MAIN, bytes32(boundary));
        vm.prank(user);
        adapter.sendMessage{value: FEE}(boundaryRecipient, PAYLOAD_40);
        assertEq(core.lastToAddress(), boundary);
    }

    function test_SendMessageRevertsZeroFeltRecipient() public {
        bytes memory zeroRecipient = NonEvmAddress.formatV1(NonEvmAddress.STARKNET_CHAIN_TYPE, SN_MAIN, bytes32(0));
        vm.prank(user);
        vm.expectRevert(NonEvmAddress.NonEvmAddressZeroFelt.selector);
        adapter.sendMessage{value: FEE}(zeroRecipient, PAYLOAD_40);
    }

    function test_SendMessageRevertsEmptyRecipient() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(InteroperableAddress.InteroperableAddressParsingError.selector, hex""));
        adapter.sendMessage{value: FEE}(hex"", PAYLOAD_40);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                CANCELLATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Sends {PAYLOAD_40} as `user` and returns the core-computed message hash + nonce.
    function _sendAsUser() internal returns (bytes32 msgHash, uint256 nonce) {
        vm.prank(user);
        (msgHash, nonce) = adapter.sendMessage{value: FEE}(recip, PAYLOAD_40);
    }

    function test_CancellationHappyPath() public {
        (bytes32 msgHash, uint256 nonce) = _sendAsUser();

        vm.expectEmit(true, true, false, true, diamond);
        emit IStarknetGatewayAdapter.StarknetCancellationStarted(user, msgHash, nonce);
        vm.prank(user);
        assertEq(adapter.startCancellation(recip, handlerSelector, PAYLOAD_40, nonce), msgHash);

        // The core enforces messageCancellationDelay() between the two steps.
        vm.warp(block.timestamp + core.CANCELLATION_DELAY());

        vm.expectEmit(true, true, false, true, diamond);
        emit IStarknetGatewayAdapter.StarknetMessageCancelled(user, msgHash, nonce);
        vm.prank(user);
        assertEq(adapter.cancel(recip, handlerSelector, PAYLOAD_40, nonce), msgHash);

        assertEq(adapter.initiatorOf(msgHash), address(0), "initiator record cleared after cancel");
        assertEq(core.l1ToL2Messages(msgHash), 0, "message cancelled on the core");
        // The escrowed fee is NOT refunded — it stays with the core.
        assertEq(address(core).balance, FEE, "fee NOT refunded on cancel");
    }

    function test_StartCancellationRevertsNonInitiator() public {
        (bytes32 msgHash, uint256 nonce) = _sendAsUser();
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IStarknetGatewayAdapter.StarknetNotInitiator.selector, msgHash, other));
        adapter.startCancellation(recip, handlerSelector, PAYLOAD_40, nonce);
    }

    function test_CancelRevertsNonInitiator() public {
        (bytes32 msgHash, uint256 nonce) = _sendAsUser();
        vm.prank(user);
        adapter.startCancellation(recip, handlerSelector, PAYLOAD_40, nonce);
        vm.warp(block.timestamp + core.CANCELLATION_DELAY());

        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IStarknetGatewayAdapter.StarknetNotInitiator.selector, msgHash, other));
        adapter.cancel(recip, handlerSelector, PAYLOAD_40, nonce);
    }

    /// @notice An altered payload re-derives a DIFFERENT message hash, which has no initiator record — even the
    ///         original initiator cannot cancel a message that was never sent.
    function test_CancelRevertsOnAlteredPayload() public {
        (, uint256 nonce) = _sendAsUser();
        bytes memory altered = bytes.concat(PAYLOAD_40, hex"ff");
        bytes32 alteredHash = core.l1ToL2MsgHash(diamond, L2_TARGET, handlerSelector, codec.encode(altered), nonce);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IStarknetGatewayAdapter.StarknetNotInitiator.selector, alteredHash, user)
        );
        adapter.cancel(recip, handlerSelector, altered, nonce);
    }

    function test_CancelBeforeDelayBubblesCoreRevert() public {
        (, uint256 nonce) = _sendAsUser();
        vm.prank(user);
        adapter.startCancellation(recip, handlerSelector, PAYLOAD_40, nonce);
        vm.warp(block.timestamp + core.CANCELLATION_DELAY() - 1);
        vm.prank(user);
        vm.expectRevert(bytes("MESSAGE_CANCELLATION_NOT_ALLOWED_YET"));
        adapter.cancel(recip, handlerSelector, PAYLOAD_40, nonce);
    }

    /// @notice SELECTOR RE-REGISTRATION REGRESSION (review finding): cancellation takes the SEND-TIME selector
    ///         explicitly instead of re-reading the mutable handler registry, so an admin re-pointing the
    ///         target's selector while a message is in flight can no longer lock the initiator out of
    ///         cancelling. The initiator gate stays sound: only the original (recipient, selector, payload,
    ///         nonce) tuple re-derives the recorded hash.
    function test_CancellationSurvivesSelectorReRegistration() public {
        (bytes32 msgHash, uint256 nonce) = _sendAsUser(); // send-time selector = handlerSelector

        // A wrong selector is harmless: it re-derives a different hash with an empty initiator record.
        bytes32 wrongHash = core.l1ToL2MsgHash(diamond, L2_TARGET, handlerSelector + 1, codec.encode(PAYLOAD_40), nonce);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IStarknetGatewayAdapter.StarknetNotInitiator.selector, wrongHash, user));
        adapter.startCancellation(recip, handlerSelector + 1, PAYLOAD_40, nonce);

        // Admin re-points the target's handler to a different selector mid-flight...
        vm.prank(admin);
        adapter.registerL2Handler(L2_TARGET, handlerSelector + 1);

        // ...and the initiator STILL cancels with the ORIGINAL send-time selector (emitted in
        // StarknetMessageSent) — the mutable registry no longer participates in cancellation.
        vm.prank(user);
        assertEq(adapter.startCancellation(recip, handlerSelector, PAYLOAD_40, nonce), msgHash);
        vm.warp(block.timestamp + core.CANCELLATION_DELAY());
        vm.prank(user);
        assertEq(adapter.cancel(recip, handlerSelector, PAYLOAD_40, nonce), msgHash);
        assertEq(adapter.initiatorOf(msgHash), address(0), "initiator cleared");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONSUME
    //////////////////////////////////////////////////////////////////////////*//

    function test_ConsumeMessageHappyPath() public {
        uint256[] memory felts = _expectedFelts40();
        core.mockSendMessageFromL2(L2_FROM, diamond, felts);
        bytes32 expectedHash = core.l2ToL1MsgHash(L2_FROM, diamond, felts);
        assertEq(core.l2ToL1Messages(expectedHash), 1, "message loaded");

        vm.expectEmit(true, false, false, true, diamond);
        emit IStarknetGatewayAdapter.StarknetMessageConsumed(L2_FROM, expectedHash, PAYLOAD_40);
        vm.prank(keeper); // permissionless: any keeper can pull
        bytes32 msgHash = adapter.consumeMessage(L2_FROM, PAYLOAD_40);

        assertEq(msgHash, expectedHash);
        assertEq(core.l2ToL1Messages(expectedHash), 0, "counter decremented");
        assertEq(core.lastConsumer(), diamond, "the core authenticated the DIAMOND as the recipient");
    }

    function test_ConsumeMessageRevertsUntrustedSender() public {
        uint256 untrusted = L2_FROM - 1;
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSelector(IStarknetGatewayAdapter.StarknetUntrustedSender.selector, untrusted));
        adapter.consumeMessage(untrusted, PAYLOAD_40);
    }

    /// @notice COUNTER semantics: the SAME message loaded twice is two DISTINCT consumes (the L2 sent twice),
    ///         and the third attempt bubbles the core's zero-counter revert.
    function test_ConsumeMessageCounterSemantics() public {
        uint256[] memory felts = _expectedFelts40();
        core.mockSendMessageFromL2(L2_FROM, diamond, felts);
        core.mockSendMessageFromL2(L2_FROM, diamond, felts);
        bytes32 msgHash = core.l2ToL1MsgHash(L2_FROM, diamond, felts);
        assertEq(core.l2ToL1Messages(msgHash), 2);

        vm.prank(keeper);
        adapter.consumeMessage(L2_FROM, PAYLOAD_40);
        assertEq(core.l2ToL1Messages(msgHash), 1);

        vm.prank(keeper);
        adapter.consumeMessage(L2_FROM, PAYLOAD_40);
        assertEq(core.l2ToL1Messages(msgHash), 0);

        vm.prank(keeper);
        vm.expectRevert(bytes("INVALID_MESSAGE_TO_CONSUME"));
        adapter.consumeMessage(L2_FROM, PAYLOAD_40);
    }

    function test_ConsumeMessageRevertsWhenNotLoaded() public {
        vm.prank(keeper);
        vm.expectRevert(bytes("INVALID_MESSAGE_TO_CONSUME"));
        adapter.consumeMessage(L2_FROM, PAYLOAD_40);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            FELT-CHUNK CODEC
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice bytes -> felts -> bytes identity for payload lengths 0..500, plus the structural invariants of
    ///         the wire format (length prefix, chunk count, every chunk < 2**248).
    function testFuzz_FeltChunkRoundtrip(bytes memory data) public view {
        vm.assume(data.length <= 500);
        uint256[] memory felts = codec.encode(data);
        assertEq(felts[0], data.length, "length prefix");
        assertEq(felts.length, 1 + (data.length + 30) / 31, "chunk count");
        for (uint256 i = 1; i < felts.length; ++i) {
            assertLt(felts[i], uint256(1) << 248, "chunk < 2**248 (a felt by construction)");
        }
        assertEq(codec.decode(felts), data, "roundtrip identity");
    }

    function test_EncodeEmptyPayload() public view {
        uint256[] memory felts = codec.encode(hex"");
        assertEq(felts.length, 1, "felts == [0]");
        assertEq(felts[0], 0);
        assertEq(codec.decode(felts), hex"");
    }

    function test_EncodeExact31Bytes() public view {
        bytes memory payload = hex"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e";
        uint256[] memory felts = codec.encode(payload);
        assertEq(felts.length, 2, "one full chunk");
        assertEq(felts[0], 31);
        assertEq(felts[1], CHUNK_0, "31 bytes fill the frame exactly (no padding)");
        assertEq(codec.decode(felts), payload);
    }

    function test_Encode32ByteBoundary() public view {
        bytes memory payload = hex"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1eab";
        uint256[] memory felts = codec.encode(payload);
        assertEq(felts.length, 3, "31 + 1 spills into a second chunk");
        assertEq(felts[0], 32);
        assertEq(felts[1], CHUNK_0);
        assertEq(felts[2], uint256(0xab) << 240, "single byte right-padded across the 31-byte frame");
        assertEq(codec.decode(felts), payload);
    }

    function test_DecodeRevertsOnMalformedFelts() public {
        // Empty array (missing length prefix).
        vm.expectRevert(IStarknetGatewayAdapter.StarknetMalformedFeltPayload.selector);
        codec.decode(new uint256[](0));

        // Wrong chunk count for the declared byte length.
        uint256[] memory wrongCount = new uint256[](2);
        wrongCount[0] = 40; // needs 2 chunks, provides 1
        vm.expectRevert(IStarknetGatewayAdapter.StarknetMalformedFeltPayload.selector);
        codec.decode(wrongCount);

        // Chunk out of the 31-byte range (>= 2**248).
        uint256[] memory tooBig = new uint256[](2);
        tooBig[0] = 31;
        tooBig[1] = uint256(1) << 248;
        vm.expectRevert(IStarknetGatewayAdapter.StarknetMalformedFeltPayload.selector);
        codec.decode(tooBig);

        // Non-canonical padding (non-zero bits below the data bytes of the final chunk).
        uint256[] memory dirtyPadding = new uint256[](2);
        dirtyPadding[0] = 1; // one data byte => 30 padding bytes that must be zero
        dirtyPadding[1] = (uint256(0xab) << 240) | 1;
        vm.expectRevert(IStarknetGatewayAdapter.StarknetMalformedFeltPayload.selector);
        codec.decode(dirtyPadding);
    }
}
