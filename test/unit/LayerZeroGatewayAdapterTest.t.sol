// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {LayerZeroGatewayAdapterTestBase} from "@lattice-test/base/LayerZeroGatewayAdapterTestBase.sol";
import {LayerZeroGatewayAdapter} from "@lattice/crosschain/LayerZeroGatewayAdapter.sol";
import {ILayerZeroGatewayAdapter} from "@lattice/interfaces/crosschain/ILayerZeroGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {
    ILayerZeroEndpointV2,
    MessagingFee,
    MessagingParams,
    MessagingReceipt,
    Origin
} from "@lattice/interfaces/external/layerzero/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "@lattice/interfaces/external/layerzero/ILayerZeroReceiver.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @notice Minimal LayerZero v2 EndpointV2 mock. Records the last `send` packet, pulls the native fee the way
///         the real endpoint does (via `msg.value`), and returns a deterministic guid + receipt. `quote`
///         returns a fixed native fee. The test drives inbound `lzReceive` by pranking as this endpoint.
contract MockLayerZeroEndpoint is ILayerZeroEndpointV2 {
    uint256 public feeAmount = 0.01 ether;
    uint32 public eid = 1;

    uint32 public lastDstEid;
    bytes32 public lastReceiver;
    bytes public lastMessage;
    bytes public lastOptions;
    bool public lastPayInLzToken;
    address public lastRefundAddress;
    uint256 public sends;

    function setFee(uint256 f) external {
        feeAmount = f;
    }

    function quote(MessagingParams calldata, address) external view returns (MessagingFee memory) {
        return MessagingFee({nativeFee: feeAmount, lzTokenFee: 0});
    }

    function send(MessagingParams calldata _params, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory)
    {
        require(msg.value >= feeAmount, "fee");
        lastDstEid = _params.dstEid;
        lastReceiver = _params.receiver;
        lastMessage = _params.message;
        lastOptions = _params.options;
        lastPayInLzToken = _params.payInLzToken;
        lastRefundAddress = _refundAddress;
        return MessagingReceipt({
            guid: keccak256(abi.encode("lz-msg", ++sends)),
            nonce: uint64(sends),
            fee: MessagingFee({nativeFee: feeAmount, lzTokenFee: 0})
        });
    }

    function setDelegate(address) external {}

    function lzToken() external pure returns (address) {
        return address(0);
    }

    function nativeToken() external pure returns (address) {
        return address(0);
    }
}

contract MockRecipient is IERC7786Recipient {
    bytes32 public lastReceiveId;
    bytes public lastSender;
    bytes public lastPayload;
    uint256 public lastValue;
    uint256 public calls;

    function receiveMessage(bytes32 receiveId, bytes calldata sender, bytes calldata payload)
        external
        payable
        returns (bytes4)
    {
        lastReceiveId = receiveId;
        lastSender = sender;
        lastPayload = payload;
        lastValue = msg.value;
        ++calls;
        return IERC7786Recipient.receiveMessage.selector;
    }
}

contract LayerZeroGatewayAdapterTest is LayerZeroGatewayAdapterTestBase {
    MockLayerZeroEndpoint lzEndpoint;
    MockRecipient recipient;

    address admin = address(0x1);
    address user = address(0x2);
    address remoteGw = address(0xA11CE);
    address finalRecipient = address(0xCAFE);

    uint256 constant REMOTE_CHAIN = 10;
    uint32 constant REMOTE_EID = 30_110; // arbitrary LayerZero-style eid
    uint128 constant DEST_GAS = 200_000;
    uint128 constant DEST_VALUE = 0;

    bytes32 remotePeer; // trusted remote adapter as bytes32
    bytes recip; // dest recipient (ERC-7930)
    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        lzEndpoint = new MockLayerZeroEndpoint();
        diamond = _deployLayerZeroGatewayAdapter(admin, address(lzEndpoint));
        adapter = LayerZeroGatewayAdapter(payable(diamond));
        recipient = new MockRecipient();

        remotePeer = bytes32(uint256(uint160(remoteGw)));
        recip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, finalRecipient);

        vm.startPrank(admin);
        adapter.registerEid(REMOTE_CHAIN, REMOTE_EID);
        adapter.registerPeer(REMOTE_CHAIN, remotePeer);
        adapter.configureDestination(REMOTE_CHAIN, DEST_GAS, DEST_VALUE);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterEid() public view {
        assertEq(adapter.getEid(REMOTE_CHAIN), REMOTE_EID);
        assertEq(adapter.getChainId(REMOTE_EID), REMOTE_CHAIN);
    }

    function test_RegisterEidRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerEid(99, 99);
    }

    function test_RegisterEidDuplicateReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILayerZeroGatewayAdapter.EidAlreadyRegistered.selector, REMOTE_CHAIN));
        adapter.registerEid(REMOTE_CHAIN, 1234);
    }

    function test_RegisterPeer() public view {
        assertEq(adapter.getPeer(REMOTE_CHAIN), remotePeer);
    }

    function test_RegisterPeerDuplicateReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILayerZeroGatewayAdapter.PeerAlreadyRegistered.selector, REMOTE_CHAIN));
        adapter.registerPeer(REMOTE_CHAIN, bytes32(uint256(0xBEEF)));
    }

    function test_ConfigureDestination() public view {
        assertEq(adapter.getDestinationGas(REMOTE_CHAIN), DEST_GAS);
        assertEq(adapter.getDestinationMsgValue(REMOTE_CHAIN), DEST_VALUE);
    }

    function test_ConfigureDestinationRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.configureDestination(REMOTE_CHAIN, 1, 0);
    }

    function test_Endpoint() public view {
        assertEq(adapter.endpoint(), address(lzEndpoint));
    }

    function test_SupportsAttributeAlwaysFalse() public view {
        assertFalse(adapter.supportsAttribute(bytes4(0x12345678)));
        assertFalse(adapter.supportsAttribute(bytes4(0)));
    }

    function test_SupportsInterfaceGatewaySource() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC7786GatewaySource).interfaceId));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    function _wireMessage(address sender, bytes memory inner) internal view returns (bytes memory) {
        return abi.encode(InteroperableAddress.formatEvmV1(block.chainid, sender), recip, inner);
    }

    function _expectedOptions(uint128 gas, uint128 value) internal pure returns (bytes memory) {
        if (value == 0) return abi.encodePacked(uint16(3), uint8(1), uint16(17), uint8(1), gas);
        return abi.encodePacked(uint16(3), uint8(1), uint16(33), uint8(1), gas, value);
    }

    function test_SendNativeFeeSubmitsToEndpoint() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        bytes32 id = adapter.sendMessage{value: 0.01 ether}(recip, hex"deadbeef", new bytes[](0));

        assertEq(id, keccak256(abi.encode("lz-msg", uint256(1))), "returns the LayerZero guid");
        assertEq(lzEndpoint.lastDstEid(), REMOTE_EID);
        assertEq(lzEndpoint.lastReceiver(), remotePeer, "receiver = trusted peer");
        assertFalse(lzEndpoint.lastPayInLzToken(), "native fee only");
        assertEq(lzEndpoint.lastRefundAddress(), user, "endpoint refunds surplus to sender");
        assertEq(lzEndpoint.lastMessage(), _wireMessage(user, hex"deadbeef"), "wire envelope");
        assertEq(lzEndpoint.lastOptions(), _expectedOptions(DEST_GAS, DEST_VALUE), "type-3 lzReceive options");
    }

    function test_SendOptionsCarryMsgValueWhenConfigured() public {
        vm.prank(admin);
        adapter.configureDestination(REMOTE_CHAIN, DEST_GAS, 1 ether);
        vm.deal(user, 1 ether);
        vm.prank(user);
        adapter.sendMessage{value: 0.01 ether}(recip, hex"01", new bytes[](0));
        assertEq(lzEndpoint.lastOptions(), _expectedOptions(DEST_GAS, 1 ether), "options carry gas + value");
    }

    function test_SendNativeFeeRefundsExcess() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        adapter.sendMessage{value: 0.05 ether}(recip, hex"01", new bytes[](0));
        // forwarded 0.01 to endpoint, refunded 0.04 to user
        assertEq(user.balance, 1 ether - 0.01 ether, "excess refunded");
        assertEq(address(lzEndpoint).balance, 0.01 ether, "endpoint got fee");
    }

    function test_SendEmitsMessageSent() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectEmit(false, false, false, false);
        emit IERC7786GatewaySource.MessageSent(bytes32(0), "", "", "", 0, new bytes[](0));
        adapter.sendMessage{value: 0.01 ether}(recip, hex"deadbeef", new bytes[](0));
    }

    function test_SendInsufficientNativeFeeReverts() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ILayerZeroGatewayAdapter.InsufficientFee.selector, 0.001 ether, 0.01 ether)
        );
        adapter.sendMessage{value: 0.001 ether}(recip, hex"01", new bytes[](0));
    }

    function test_SendUnknownDestinationReverts() public {
        bytes memory unknown = InteroperableAddress.formatEvmV1(999, finalRecipient);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ILayerZeroGatewayAdapter.UnknownDestinationChain.selector, 999));
        adapter.sendMessage(unknown, hex"01", new bytes[](0));
    }

    function test_SendUnconfiguredDestinationReverts() public {
        // eid + peer registered but no gas configured
        vm.startPrank(admin);
        adapter.registerEid(77, 7777);
        adapter.registerPeer(77, bytes32(uint256(0xD00D)));
        vm.stopPrank();
        bytes memory dest = InteroperableAddress.formatEvmV1(77, finalRecipient);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ILayerZeroGatewayAdapter.DestinationNotConfigured.selector, 77));
        adapter.sendMessage(dest, hex"01", new bytes[](0));
    }

    function test_SendRejectsAttributes() public {
        bytes[] memory attrs = new bytes[](1);
        attrs[0] = abi.encodeWithSelector(bytes4(0xaabbccdd));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC7786GatewaySource.UnsupportedAttribute.selector, bytes4(0xaabbccdd)));
        adapter.sendMessage(recip, hex"01", attrs);
    }

    function test_QuoteFee() public view {
        assertEq(adapter.quoteFee(recip, hex"deadbeef"), 0.01 ether);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECEIVE
    //////////////////////////////////////////////////////////////////////////*//

    function _origin(bytes32 sender) internal pure returns (Origin memory) {
        return Origin({srcEid: REMOTE_EID, sender: sender, nonce: 1});
    }

    function _inboundMessage(bytes memory inner) internal view returns (bytes memory) {
        bytes memory senderInterop = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0x5151));
        bytes memory localRecip = InteroperableAddress.formatEvmV1(block.chainid, address(recipient));
        return abi.encode(senderInterop, localRecip, inner);
    }

    function test_ReceiveDeliversToRecipient() public {
        bytes32 guid = keccak256("guid-1");
        vm.prank(address(lzEndpoint));
        adapter.lzReceive(_origin(remotePeer), guid, _inboundMessage(hex"c0ffee"), address(0), "");

        assertEq(recipient.calls(), 1);
        assertEq(recipient.lastReceiveId(), guid, "receiveId = layerzero guid");
        assertEq(recipient.lastPayload(), hex"c0ffee");
        assertEq(recipient.lastSender(), InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0x5151)));
    }

    function test_ReceiveForwardsValue() public {
        bytes32 guid = keccak256("guid-value");
        vm.deal(address(lzEndpoint), 1 ether);
        vm.prank(address(lzEndpoint));
        adapter.lzReceive{value: 0.5 ether}(_origin(remotePeer), guid, _inboundMessage(hex"01"), address(0), "");
        assertEq(recipient.lastValue(), 0.5 ether, "native value forwarded to recipient");
    }

    function test_ReceiveReplayReverts() public {
        bytes32 guid = keccak256("guid-1");
        vm.startPrank(address(lzEndpoint));
        adapter.lzReceive(_origin(remotePeer), guid, _inboundMessage(hex"01"), address(0), "");
        vm.expectRevert(
            abi.encodeWithSelector(ILayerZeroGatewayAdapter.MessageAlreadyExecuted.selector, REMOTE_CHAIN, guid)
        );
        adapter.lzReceive(_origin(remotePeer), guid, _inboundMessage(hex"01"), address(0), "");
        vm.stopPrank();
    }

    function test_ReceiveWrongEndpointReverts() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ILayerZeroGatewayAdapter.NotEndpoint.selector, user));
        adapter.lzReceive(_origin(remotePeer), keccak256("x"), _inboundMessage(hex"01"), address(0), "");
    }

    function test_ReceiveWrongOriginReverts() public {
        bytes32 wrongSender = bytes32(uint256(uint160(address(0xDEAD))));
        vm.prank(address(lzEndpoint));
        vm.expectRevert(
            abi.encodeWithSelector(ILayerZeroGatewayAdapter.InvalidOriginGateway.selector, REMOTE_EID, wrongSender)
        );
        adapter.lzReceive(_origin(wrongSender), keccak256("x"), _inboundMessage(hex"01"), address(0), "");
    }

    function test_ReceiveUnknownEidReverts() public {
        Origin memory o = Origin({srcEid: 424242, sender: remotePeer, nonce: 1});
        vm.prank(address(lzEndpoint));
        vm.expectRevert(
            abi.encodeWithSelector(ILayerZeroGatewayAdapter.InvalidOriginGateway.selector, uint32(424242), remotePeer)
        );
        adapter.lzReceive(o, keccak256("x"), _inboundMessage(hex"01"), address(0), "");
    }

    /// @notice Hardening: a message whose recipient targets a different chain than this one is rejected
    ///         (defense-in-depth against a rogue/misconfigured trusted peer misdirecting delivery).
    function test_ReceiveWrongDestinationChainReverts() public {
        bytes memory senderInterop = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0x5151));
        bytes memory wrongChainRecip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(recipient));
        bytes memory message = abi.encode(senderInterop, wrongChainRecip, hex"01");
        vm.prank(address(lzEndpoint));
        vm.expectRevert(abi.encodeWithSelector(ILayerZeroGatewayAdapter.WrongDestinationChain.selector, REMOTE_CHAIN));
        adapter.lzReceive(_origin(remotePeer), keccak256("wrongchain"), message, address(0), "");
    }

    /// @notice Hardening: an eid registered before its peer cannot satisfy origin auth via a zero sender.
    function test_ReceiveUnconfiguredPeerReverts() public {
        uint256 newChain = 20;
        uint32 newEid = 30_200;
        vm.prank(admin);
        adapter.registerEid(newChain, newEid); // peer intentionally left unset

        Origin memory o = Origin({srcEid: newEid, sender: bytes32(0), nonce: 1});
        vm.prank(address(lzEndpoint));
        vm.expectRevert(
            abi.encodeWithSelector(ILayerZeroGatewayAdapter.InvalidOriginGateway.selector, newEid, bytes32(0))
        );
        adapter.lzReceive(o, keccak256("nopeer"), _inboundMessage(hex"01"), address(0), "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              RECEIVER POLICY
    //////////////////////////////////////////////////////////////////////////*//

    function test_AllowInitializePathTrueForPeer() public view {
        assertTrue(adapter.allowInitializePath(_origin(remotePeer)));
    }

    function test_AllowInitializePathFalseForNonPeer() public view {
        assertFalse(adapter.allowInitializePath(_origin(bytes32(uint256(uint160(address(0xDEAD)))))));
    }

    function test_AllowInitializePathFalseForUnknownEid() public view {
        assertFalse(adapter.allowInitializePath(Origin({srcEid: 424242, sender: remotePeer, nonce: 1})));
    }

    function test_NextNonceIsZeroUnordered() public view {
        assertEq(adapter.nextNonce(REMOTE_EID, remotePeer), 0);
    }
}
