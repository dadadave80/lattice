// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {
    L1ToL2CrossDomainMessengerGatewayAdapterTestBase
} from "@lattice-test/base/L1ToL2CrossDomainMessengerGatewayAdapterTestBase.sol";
import {L2_CROSS_DOMAIN_MESSENGER} from "@lattice/crosschain/libraries/L1ToL2CrossDomainMessengerGatewayAdapterLib.sol";
import {
    L1ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/crosschain/optimism/L1ToL2CrossDomainMessengerGatewayAdapter.sol";
import {
    IL1ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/interfaces/crosschain/IL1ToL2CrossDomainMessengerGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {ICrossDomainMessenger} from "@lattice/interfaces/external/optimism/ICrossDomainMessenger.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @notice Minimal canonical OP Stack L1<->L2 `CrossDomainMessenger` mock. `sendMessage` records `(target, message,
///         minGasLimit)` and returns nothing (VOID). A settable `xDomainMessageSender()` returns the authenticated
///         counterpart sender the inbound test wants — the harness drives inbound delivery by pranking AS this
///         messenger (etched at the fixed predeploy address).
contract MockCrossDomainMessenger is ICrossDomainMessenger {
    address public lastTarget;
    bytes public lastMessage;
    uint32 public lastMinGasLimit;
    uint256 public sends;

    address internal _xDomainSender;

    function setXDomainMessageSender(address sender) external {
        _xDomainSender = sender;
    }

    function sendMessage(address _target, bytes calldata _message, uint32 _minGasLimit) external payable {
        lastTarget = _target;
        lastMessage = _message;
        lastMinGasLimit = _minGasLimit;
        ++sends;
    }

    function xDomainMessageSender() external view returns (address) {
        return _xDomainSender;
    }

    function otherMessenger() external view returns (ICrossDomainMessenger) {
        return ICrossDomainMessenger(address(0));
    }

    function successfulMessages(bytes32) external pure returns (bool) {
        return false;
    }

    function messageNonce() external pure returns (uint256) {
        return 0;
    }

    function MESSAGE_VERSION() external pure returns (uint16) {
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

contract L1ToL2CrossDomainMessengerGatewayAdapterTest is L1ToL2CrossDomainMessengerGatewayAdapterTestBase {
    MockCrossDomainMessenger messenger; // handle at the etched predeploy address
    MockRecipient recipient;

    address admin = address(0x1);
    address user = address(0x2);
    address counterpart = address(0xA11CE);
    address finalRecipient = address(0xCAFE);
    address remoteSender = address(0x5151);

    uint256 constant COUNTERPART_CHAIN = 10;
    uint32 constant MIN_GAS = 200_000;

    bytes recip; // dest recipient (ERC-7930)
    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        // Etch the mock at the fixed messenger predeploy so both outbound sends and inbound context reads hit it.
        MockCrossDomainMessenger impl = new MockCrossDomainMessenger();
        vm.etch(L2_CROSS_DOMAIN_MESSENGER, address(impl).code);
        messenger = MockCrossDomainMessenger(L2_CROSS_DOMAIN_MESSENGER);

        diamond = _deployL1ToL2CrossDomainMessengerGatewayAdapter(admin, COUNTERPART_CHAIN, counterpart, MIN_GAS);
        adapter = L1ToL2CrossDomainMessengerGatewayAdapter(payable(diamond));
        recipient = new MockRecipient();

        recip = InteroperableAddress.formatEvmV1(COUNTERPART_CHAIN, finalRecipient);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_Messenger() public view {
        assertEq(adapter.messenger(), L2_CROSS_DOMAIN_MESSENGER);
    }

    function test_InitSeedsCounterpart() public view {
        assertEq(adapter.counterpartChainId(), COUNTERPART_CHAIN);
        assertEq(adapter.counterpartAdapter(), counterpart);
        assertEq(adapter.minGasLimit(), MIN_GAS);
    }

    function test_SetCounterpart() public {
        vm.prank(admin);
        adapter.setCounterpart(77, address(0xBEEF));
        assertEq(adapter.counterpartChainId(), 77);
        assertEq(adapter.counterpartAdapter(), address(0xBEEF));
    }

    function test_SetCounterpartRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.setCounterpart(77, address(0xBEEF));
    }

    function test_SetCounterpartRejectsZero() public {
        vm.prank(admin);
        vm.expectRevert(IL1ToL2CrossDomainMessengerGatewayAdapter.InvalidCounterpartAdapter.selector);
        adapter.setCounterpart(77, address(0));
    }

    function test_SetMinGasLimit() public {
        vm.prank(admin);
        adapter.setMinGasLimit(500_000);
        assertEq(adapter.minGasLimit(), 500_000);
    }

    function test_SetMinGasLimitRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.setMinGasLimit(500_000);
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
            IL1ToL2CrossDomainMessengerGatewayAdapter.receiveCrossChainMessage,
            (InteroperableAddress.formatEvmV1(block.chainid, sender), recip, payload, nonce)
        );
    }

    /// @dev Receive-side id: namespaced by the SOURCE chain, which from THIS adapter's view is the counterpart.
    function _expectedId(uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(COUNTERPART_CHAIN, nonce));
    }

    /// @dev Send-side id: namespaced by the SOURCE chain (this one), so it equals what the counterpart derives on
    ///      receipt and never collides with this adapter's inbound (counterpart-namespaced) ids.
    function _sendId(uint256 nonce) internal view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, nonce));
    }

    function test_SendSubmitsToMessenger() public {
        vm.prank(user);
        bytes32 id = adapter.sendMessage(recip, hex"deadbeef", new bytes[](0));

        // First outbound uses nonce 0 (the source-minted monotonic counter); id namespaced by the source chain.
        assertEq(id, _sendId(0), "returns (source, nonce) id");
        assertEq(messenger.lastTarget(), counterpart, "target = counterpart adapter");
        assertEq(messenger.lastMinGasLimit(), MIN_GAS, "relays with configured minGasLimit");
        assertEq(messenger.lastMessage(), _wireMessage(user, hex"deadbeef", 0), "wire envelope = encodeCall(inbound)");
    }

    function test_SendEmitsMessageSent() public {
        vm.prank(user);
        vm.expectEmit(true, false, false, false);
        emit IERC7786GatewaySource.MessageSent(_sendId(0), "", "", "", 0, new bytes[](0));
        adapter.sendMessage(recip, hex"deadbeef", new bytes[](0));
    }

    function test_SendMintsMonotonicNonce() public {
        vm.startPrank(user);
        bytes32 id0 = adapter.sendMessage(recip, hex"01", new bytes[](0));
        bytes32 id1 = adapter.sendMessage(recip, hex"01", new bytes[](0));
        vm.stopPrank();

        assertEq(id0, _sendId(0));
        assertEq(id1, _sendId(1));
        assertTrue(id0 != id1, "distinct ids per outbound send");
    }

    /// @notice Hardening (adversarial finding): a zero relay minGasLimit is rejected (delivery would out-of-gas).
    function test_SetMinGasLimitRejectsZero() public {
        vm.prank(admin);
        vm.expectRevert(IL1ToL2CrossDomainMessengerGatewayAdapter.InvalidMinGasLimit.selector);
        adapter.setMinGasLimit(0);
    }

    function test_SendRejectsValue() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IL1ToL2CrossDomainMessengerGatewayAdapter.UnexpectedValue.selector, 0.5 ether)
        );
        adapter.sendMessage{value: 0.5 ether}(recip, hex"01", new bytes[](0));
    }

    function test_SendUnknownDestinationReverts() public {
        bytes memory unknown = InteroperableAddress.formatEvmV1(999, finalRecipient);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IL1ToL2CrossDomainMessengerGatewayAdapter.UnknownDestinationChain.selector, 999)
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
        return InteroperableAddress.formatEvmV1(COUNTERPART_CHAIN, remoteSender);
    }

    function _localRecip() internal view returns (bytes memory) {
        return InteroperableAddress.formatEvmV1(block.chainid, address(recipient));
    }

    function test_ReceiveDeliversToRecipient() public {
        messenger.setXDomainMessageSender(counterpart);
        bytes memory sender = _senderInterop();
        bytes memory rcp = _localRecip();

        vm.prank(L2_CROSS_DOMAIN_MESSENGER);
        adapter.receiveCrossChainMessage(sender, rcp, hex"c0ffee", 0);

        assertEq(recipient.calls(), 1);
        assertEq(recipient.lastReceiveId(), _expectedId(0), "receiveId = (counterpart, nonce) id");
        assertEq(recipient.lastPayload(), hex"c0ffee");
        assertEq(recipient.lastSender(), sender);
    }

    function test_ReceiveReplayReverts() public {
        messenger.setXDomainMessageSender(counterpart);
        bytes memory sender = _senderInterop();
        bytes memory rcp = _localRecip();

        vm.startPrank(L2_CROSS_DOMAIN_MESSENGER);
        adapter.receiveCrossChainMessage(sender, rcp, hex"01", 5);
        vm.expectRevert(
            abi.encodeWithSelector(
                IL1ToL2CrossDomainMessengerGatewayAdapter.MessageAlreadyExecuted.selector, _expectedId(5)
            )
        );
        adapter.receiveCrossChainMessage(sender, rcp, hex"01", 5); // same nonce = same id = replay
        vm.stopPrank();
    }

    /// @notice Regression for the adversarial finding: two byte-identical messages carrying DISTINCT source
    ///         nonces must BOTH deliver with DISTINCT ids — content-keyed dedup would permanently drop the second
    ///         and hand the recipient a non-unique id.
    function test_ReceiveDuplicateContentDistinctNoncesBothDeliver() public {
        messenger.setXDomainMessageSender(counterpart);
        bytes memory sender = _senderInterop();
        bytes memory rcp = _localRecip();

        vm.startPrank(L2_CROSS_DOMAIN_MESSENGER);
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
        messenger.setXDomainMessageSender(counterpart);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IL1ToL2CrossDomainMessengerGatewayAdapter.NotMessenger.selector, user));
        adapter.receiveCrossChainMessage(_senderInterop(), _localRecip(), hex"01", 0);
    }

    function test_ReceiveWrongOriginReverts() public {
        // Authenticated counterpart sender is NOT the configured counterpart adapter.
        address rogue = address(0xDEAD);
        messenger.setXDomainMessageSender(rogue);
        vm.prank(L2_CROSS_DOMAIN_MESSENGER);
        vm.expectRevert(
            abi.encodeWithSelector(IL1ToL2CrossDomainMessengerGatewayAdapter.InvalidOriginGateway.selector, rogue)
        );
        adapter.receiveCrossChainMessage(_senderInterop(), _localRecip(), hex"01", 0);
    }

    function test_ReceiveZeroXDomainSenderReverts() public {
        // A zero xDomainMessageSender (no message being relayed) can never satisfy auth.
        messenger.setXDomainMessageSender(address(0));
        vm.prank(L2_CROSS_DOMAIN_MESSENGER);
        vm.expectRevert(
            abi.encodeWithSelector(IL1ToL2CrossDomainMessengerGatewayAdapter.InvalidOriginGateway.selector, address(0))
        );
        adapter.receiveCrossChainMessage(_senderInterop(), _localRecip(), hex"01", 0);
    }

    function test_ReceiveWrongDestinationChainReverts() public {
        messenger.setXDomainMessageSender(counterpart);
        // recipient targets COUNTERPART_CHAIN, not THIS chain
        bytes memory wrongChainRecip = InteroperableAddress.formatEvmV1(COUNTERPART_CHAIN, address(recipient));
        vm.prank(L2_CROSS_DOMAIN_MESSENGER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IL1ToL2CrossDomainMessengerGatewayAdapter.WrongDestinationChain.selector, COUNTERPART_CHAIN
            )
        );
        adapter.receiveCrossChainMessage(_senderInterop(), wrongChainRecip, hex"01", 0);
    }
}
