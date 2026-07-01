// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {
    L2ToL2CrossDomainMessengerGatewayAdapterTestBase
} from "@lattice-test/base/L2ToL2CrossDomainMessengerGatewayAdapterTestBase.sol";
import {
    L2ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/crosschain/L2ToL2CrossDomainMessengerGatewayAdapter.sol";
import {
    L2_TO_L2_CROSS_DOMAIN_MESSENGER
} from "@lattice/crosschain/libraries/L2ToL2CrossDomainMessengerGatewayAdapterLib.sol";
import {
    IL2ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/interfaces/crosschain/IL2ToL2CrossDomainMessengerGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";
import {IL2ToL2CrossDomainMessenger, Identifier} from "@lattice/interfaces/external/IL2ToL2CrossDomainMessenger.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @notice Minimal OP Superchain `L2ToL2CrossDomainMessenger` mock. `sendMessage` records `(destination, target,
///         message)` and returns a deterministic messageHash. A settable `crossDomainMessageContext()` returns the
///         authenticated `(sender, source)` the inbound test wants — the harness drives inbound delivery by
///         pranking AS this messenger (etched at the fixed predeploy address).
contract MockL2ToL2Messenger is IL2ToL2CrossDomainMessenger {
    uint256 public lastDestination;
    address public lastTarget;
    bytes public lastMessage;
    uint256 public sends;

    address internal _ctxSender;
    uint256 internal _ctxSource;

    function setContext(address sender, uint256 source) external {
        _ctxSender = sender;
        _ctxSource = source;
    }

    function sendMessage(uint256 _destination, address _target, bytes calldata _message)
        external
        returns (bytes32 messageHash_)
    {
        lastDestination = _destination;
        lastTarget = _target;
        lastMessage = _message;
        return keccak256(abi.encode("l2l2-msg", ++sends));
    }

    function relayMessage(Identifier calldata, bytes calldata) external payable returns (bytes memory) {
        return "";
    }

    function crossDomainMessageContext() external view returns (address sender_, uint256 source_) {
        return (_ctxSender, _ctxSource);
    }

    function crossDomainMessageSender() external view returns (address) {
        return _ctxSender;
    }

    function crossDomainMessageSource() external view returns (uint256) {
        return _ctxSource;
    }

    function successfulMessages(bytes32) external pure returns (bool) {
        return false;
    }

    function messageVersion() external pure returns (uint16) {
        return 0;
    }

    function messageNonce() external pure returns (uint256) {
        return 0;
    }
}

contract MockRecipient is IERC7786Recipient {
    bytes32 public lastReceiveId;
    bytes public lastSender;
    bytes public lastPayload;
    uint256 public calls;

    function receiveMessage(bytes32 receiveId, bytes calldata sender, bytes calldata payload)
        external
        payable
        returns (bytes4)
    {
        lastReceiveId = receiveId;
        lastSender = sender;
        lastPayload = payload;
        ++calls;
        return IERC7786Recipient.receiveMessage.selector;
    }
}

contract L2ToL2CrossDomainMessengerGatewayAdapterTest is L2ToL2CrossDomainMessengerGatewayAdapterTestBase {
    MockL2ToL2Messenger messenger; // handle at the etched predeploy address
    MockRecipient recipient;

    address admin = address(0x1);
    address user = address(0x2);
    address remoteAdapter = address(0xA11CE);
    address finalRecipient = address(0xCAFE);
    address remoteSender = address(0x5151);

    uint256 constant REMOTE_CHAIN = 10;

    bytes recip; // dest recipient (ERC-7930)
    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        // Etch the mock at the fixed messenger predeploy so both outbound sends and inbound context reads hit it.
        MockL2ToL2Messenger impl = new MockL2ToL2Messenger();
        vm.etch(L2_TO_L2_CROSS_DOMAIN_MESSENGER, address(impl).code);
        messenger = MockL2ToL2Messenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER);

        diamond = _deployL2ToL2CrossDomainMessengerGatewayAdapter(admin);
        adapter = L2ToL2CrossDomainMessengerGatewayAdapter(payable(diamond));
        recipient = new MockRecipient();

        recip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, finalRecipient);

        vm.prank(admin);
        adapter.registerRemoteAdapter(REMOTE_CHAIN, remoteAdapter);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_Messenger() public view {
        assertEq(adapter.messenger(), L2_TO_L2_CROSS_DOMAIN_MESSENGER);
    }

    function test_RegisterRemoteAdapter() public view {
        assertEq(adapter.getRemoteAdapter(REMOTE_CHAIN), remoteAdapter);
    }

    function test_RegisterRemoteAdapterRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerRemoteAdapter(99, address(0xBEEF));
    }

    function test_RegisterRemoteAdapterDuplicateReverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IL2ToL2CrossDomainMessengerGatewayAdapter.RemoteAdapterAlreadyRegistered.selector, REMOTE_CHAIN
            )
        );
        adapter.registerRemoteAdapter(REMOTE_CHAIN, address(0xBEEF));
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

    function _wireMessage(address sender, bytes memory payload, uint256 nonce) internal view returns (bytes memory) {
        return abi.encodeCall(
            IL2ToL2CrossDomainMessengerGatewayAdapter.receiveCrossChainMessage,
            (InteroperableAddress.formatEvmV1(block.chainid, sender), recip, payload, nonce)
        );
    }

    function test_SendSubmitsToMessenger() public {
        vm.prank(user);
        bytes32 id = adapter.sendMessage(recip, hex"deadbeef", new bytes[](0));

        assertEq(id, keccak256(abi.encode("l2l2-msg", uint256(1))), "returns the messenger messageHash");
        assertEq(messenger.lastDestination(), REMOTE_CHAIN, "routes by bare chainId");
        assertEq(messenger.lastTarget(), remoteAdapter, "target = trusted remote adapter");
        // First outbound uses nonce 0 (the source-minted monotonic counter).
        assertEq(messenger.lastMessage(), _wireMessage(user, hex"deadbeef", 0), "wire envelope = encodeCall(inbound)");
    }

    function test_SendEmitsMessageSent() public {
        vm.prank(user);
        vm.expectEmit(false, false, false, false);
        emit IERC7786GatewaySource.MessageSent(bytes32(0), "", "", "", 0, new bytes[](0));
        adapter.sendMessage(recip, hex"deadbeef", new bytes[](0));
    }

    function test_SendRejectsValue() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IL2ToL2CrossDomainMessengerGatewayAdapter.UnexpectedValue.selector, 0.5 ether)
        );
        adapter.sendMessage{value: 0.5 ether}(recip, hex"01", new bytes[](0));
    }

    function test_SendUnknownDestinationReverts() public {
        bytes memory unknown = InteroperableAddress.formatEvmV1(999, finalRecipient);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IL2ToL2CrossDomainMessengerGatewayAdapter.UnknownDestinationChain.selector, 999)
        );
        adapter.sendMessage(unknown, hex"01", new bytes[](0));
    }

    function test_SendRejectsAttributes() public {
        bytes[] memory attrs = new bytes[](1);
        attrs[0] = abi.encodeWithSelector(bytes4(0xaabbccdd));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC7786GatewaySource.UnsupportedAttribute.selector, bytes4(0xaabbccdd)));
        adapter.sendMessage(recip, hex"01", attrs);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECEIVE
    //////////////////////////////////////////////////////////////////////////*//

    function _senderInterop() internal view returns (bytes memory) {
        return InteroperableAddress.formatEvmV1(REMOTE_CHAIN, remoteSender);
    }

    function _localRecip() internal view returns (bytes memory) {
        return InteroperableAddress.formatEvmV1(block.chainid, address(recipient));
    }

    function _expectedId(uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(REMOTE_CHAIN, nonce));
    }

    function test_ReceiveDeliversToRecipient() public {
        messenger.setContext(remoteAdapter, REMOTE_CHAIN);
        bytes memory sender = _senderInterop();
        bytes memory rcp = _localRecip();

        vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        adapter.receiveCrossChainMessage(sender, rcp, hex"c0ffee", 0);

        assertEq(recipient.calls(), 1);
        assertEq(recipient.lastReceiveId(), _expectedId(0), "receiveId = (source, nonce) id");
        assertEq(recipient.lastPayload(), hex"c0ffee");
        assertEq(recipient.lastSender(), sender);
    }

    function test_ReceiveReplayReverts() public {
        messenger.setContext(remoteAdapter, REMOTE_CHAIN);
        bytes memory sender = _senderInterop();
        bytes memory rcp = _localRecip();

        vm.startPrank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        adapter.receiveCrossChainMessage(sender, rcp, hex"01", 5);
        vm.expectRevert(
            abi.encodeWithSelector(
                IL2ToL2CrossDomainMessengerGatewayAdapter.MessageAlreadyExecuted.selector, REMOTE_CHAIN, _expectedId(5)
            )
        );
        adapter.receiveCrossChainMessage(sender, rcp, hex"01", 5); // same nonce = same id = replay
        vm.stopPrank();
    }

    /// @notice Regression for the adversarial finding: two byte-identical messages carrying DISTINCT source
    ///         nonces must BOTH deliver with DISTINCT ids — content-keyed dedup would permanently drop the second
    ///         and hand the recipient a non-unique id.
    function test_ReceiveDuplicateContentDistinctNoncesBothDeliver() public {
        messenger.setContext(remoteAdapter, REMOTE_CHAIN);
        bytes memory sender = _senderInterop();
        bytes memory rcp = _localRecip();

        vm.startPrank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        adapter.receiveCrossChainMessage(sender, rcp, hex"01", 1);
        bytes32 id1 = recipient.lastReceiveId();
        adapter.receiveCrossChainMessage(sender, rcp, hex"01", 2); // identical content, different nonce
        bytes32 id2 = recipient.lastReceiveId();
        vm.stopPrank();

        assertEq(recipient.calls(), 2, "both identical-content messages delivered");
        assertTrue(id1 != id2, "distinct ids for distinct nonces");
        assertEq(id1, _expectedId(1));
        assertEq(id2, _expectedId(2));
    }

    function test_ReceiveWrongMessengerReverts() public {
        messenger.setContext(remoteAdapter, REMOTE_CHAIN);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IL2ToL2CrossDomainMessengerGatewayAdapter.NotMessenger.selector, user));
        adapter.receiveCrossChainMessage(_senderInterop(), _localRecip(), hex"01", 0);
    }

    function test_ReceiveWrongOriginReverts() public {
        // Authenticated cross-domain sender is NOT the registered remote adapter for the source chain.
        address rogue = address(0xDEAD);
        messenger.setContext(rogue, REMOTE_CHAIN);
        vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IL2ToL2CrossDomainMessengerGatewayAdapter.InvalidOriginGateway.selector, REMOTE_CHAIN, rogue
            )
        );
        adapter.receiveCrossChainMessage(_senderInterop(), _localRecip(), hex"01", 0);
    }

    function test_ReceiveUnregisteredSourceReverts() public {
        // Source chain 42 has no registered remote adapter; a zero-sender context cannot satisfy auth.
        messenger.setContext(address(0), 42);
        vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IL2ToL2CrossDomainMessengerGatewayAdapter.InvalidOriginGateway.selector, uint256(42), address(0)
            )
        );
        adapter.receiveCrossChainMessage(_senderInterop(), _localRecip(), hex"01", 0);
    }

    function test_ReceiveWrongDestinationChainReverts() public {
        messenger.setContext(remoteAdapter, REMOTE_CHAIN);
        // recipient targets REMOTE_CHAIN, not THIS chain
        bytes memory wrongChainRecip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(recipient));
        vm.prank(L2_TO_L2_CROSS_DOMAIN_MESSENGER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IL2ToL2CrossDomainMessengerGatewayAdapter.WrongDestinationChain.selector, REMOTE_CHAIN
            )
        );
        adapter.receiveCrossChainMessage(_senderInterop(), wrongChainRecip, hex"01", 0);
    }

    function test_RegisterRemoteAdapterRejectsZero() public {
        vm.prank(admin);
        vm.expectRevert(IL2ToL2CrossDomainMessengerGatewayAdapter.InvalidRemoteAdapter.selector);
        adapter.registerRemoteAdapter(999, address(0));
    }
}
