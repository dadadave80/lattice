// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {CrosschainLinkTestBase} from "@lattice-test/base/CrosschainLinkTestBase.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {ICrosschainLink} from "@lattice/interfaces/crosschain/ICrosschainLink.sol";
import {IERC7786MessageHandler} from "@lattice/interfaces/crosschain/IERC7786MessageHandler.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

/// @notice Minimal ERC-7786 gateway: records the last send and returns a fixed id.
contract MockGateway is IERC7786GatewaySource {
    bytes public lastRecipient;
    bytes public lastPayload;
    bytes32 public constant SEND_ID = bytes32(uint256(0xABCD));

    function supportsAttribute(bytes4) external pure returns (bool) {
        return false;
    }

    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata)
        external
        payable
        returns (bytes32)
    {
        lastRecipient = recipient;
        lastPayload = payload;
        return SEND_ID;
    }
}

/// @notice Minimal message handler: records the last call.
contract MockHandler is IERC7786MessageHandler {
    bytes32 public lastReceiveId;
    bytes public lastSender;
    bytes public lastPayload;
    uint256 public calls;

    function processMessage(bytes32 receiveId, bytes calldata sender, bytes calldata payload) external {
        lastReceiveId = receiveId;
        lastSender = sender;
        lastPayload = payload;
        ++calls;
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

contract CrosschainLinkTest is CrosschainLinkTestBase {
    address internal diamond; // the assembled crosschain-link diamond
    CrosschainLink link; // typed handle on the diamond (messaging calls dispatch through it)
    MockGateway gateway;
    MockHandler handler;

    address admin = address(0x1);
    address user = address(0x2);
    address remoteAddr = address(0xBEEF);

    uint256 constant REMOTE_CHAIN = 10;
    bytes4 constant TAG = 0x11223344;
    bytes32 constant RECEIVE_ID = keccak256("msg-1");

    bytes counterpart; // full interop address of the remote (chain + addr)
    bytes chainOnly; // chain-only interop address

    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        diamond = _deployCrosschainLink(admin);
        link = CrosschainLink(diamond);
        gateway = new MockGateway();
        handler = new MockHandler();

        counterpart = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, remoteAddr);
        chainOnly = InteroperableAddress.formatEvmV1(REMOTE_CHAIN);
    }

    function _payload() internal pure returns (bytes memory) {
        return bytes.concat(TAG, hex"deadbeef");
    }

    function _register() internal {
        vm.startPrank(admin);
        link.setLink(address(gateway), counterpart, false);
        link.setHandler(TAG, address(handler));
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 SET LINK
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetLinkByAdmin() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit ICrosschainLink.LinkRegistered(address(gateway), counterpart);
        link.setLink(address(gateway), counterpart, false);

        (address g, bytes memory c) = link.getLink(chainOnly);
        assertEq(g, address(gateway));
        assertEq(c, counterpart);
    }

    function test_SetLinkRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        link.setLink(address(gateway), counterpart, false);
    }

    function test_SetLinkRevertsAlreadyRegistered() public {
        vm.startPrank(admin);
        link.setLink(address(gateway), counterpart, false);
        vm.expectRevert(abi.encodeWithSelector(ICrosschainLink.CrosschainLinkAlreadyRegistered.selector, chainOnly));
        link.setLink(address(gateway), counterpart, false);
        vm.stopPrank();
    }

    function test_SetLinkAllowOverride() public {
        vm.startPrank(admin);
        link.setLink(address(gateway), counterpart, false);
        MockGateway gateway2 = new MockGateway();
        link.setLink(address(gateway2), counterpart, true);
        vm.stopPrank();

        (address g,) = link.getLink(chainOnly);
        assertEq(g, address(gateway2));
    }

    function test_SetLinkRevertsZeroGateway() public {
        vm.prank(admin);
        vm.expectRevert(ICrosschainLink.CrosschainZeroGateway.selector);
        link.setLink(address(0), counterpart, false);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                SET HANDLER
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetHandlerByAdmin() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit ICrosschainLink.HandlerRegistered(TAG, address(handler));
        link.setHandler(TAG, address(handler));

        assertEq(link.getHandler(TAG), address(handler));
    }

    function test_SetHandlerRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        link.setHandler(TAG, address(handler));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              RECEIVE MESSAGE
    //////////////////////////////////////////////////////////////////////////*//

    function test_ReceiveMessageRoutesToHandler() public {
        _register();

        vm.prank(address(gateway));
        vm.expectEmit(true, true, false, true);
        emit ICrosschainLink.MessageProcessed(RECEIVE_ID, TAG, address(handler));
        bytes4 magic = link.receiveMessage(RECEIVE_ID, counterpart, _payload());

        assertEq(magic, IERC7786Recipient.receiveMessage.selector);
        assertEq(handler.calls(), 1);
        assertEq(handler.lastReceiveId(), RECEIVE_ID);
        assertEq(handler.lastSender(), counterpart);
        assertEq(handler.lastPayload(), hex"deadbeef"); // leading tag stripped
        assertTrue(link.isProcessed(address(gateway), RECEIVE_ID));
    }

    function test_ReceiveMessageRevertsUnauthorizedGateway() public {
        _register();
        vm.prank(user); // not the registered gateway
        vm.expectRevert(
            abi.encodeWithSelector(ICrosschainLink.CrosschainUnauthorizedGateway.selector, user, counterpart)
        );
        link.receiveMessage(RECEIVE_ID, counterpart, _payload());
    }

    function test_ReceiveMessageRevertsWrongSender() public {
        _register();
        // Same source chain (link + gateway match) but a different, unauthorized sender address.
        bytes memory wrongSender = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0xDEAD));
        vm.prank(address(gateway));
        vm.expectRevert(
            abi.encodeWithSelector(
                ICrosschainLink.CrosschainUnauthorizedGateway.selector, address(gateway), wrongSender
            )
        );
        link.receiveMessage(RECEIVE_ID, wrongSender, _payload());
    }

    function test_ReceiveMessageReplayReverts() public {
        _register();
        vm.startPrank(address(gateway));
        link.receiveMessage(RECEIVE_ID, counterpart, _payload());
        vm.expectRevert(abi.encodeWithSelector(ICrosschainLink.CrosschainMessageAlreadyProcessed.selector, RECEIVE_ID));
        link.receiveMessage(RECEIVE_ID, counterpart, _payload());
        vm.stopPrank();
    }

    function test_ReceiveSameIdDifferentGatewaysBothSucceed() public {
        _register(); // chain REMOTE_CHAIN via `gateway`, handler under TAG
        // A second, independent link: different chain served by a different gateway.
        MockGateway gateway2 = new MockGateway();
        bytes memory counterpart2 = InteroperableAddress.formatEvmV1(20, address(0xD00D));
        vm.prank(admin);
        link.setLink(address(gateway2), counterpart2, false);

        // Two distinct, authentic messages that happen to share a receiveId (ERC-7786 only guarantees
        // receiveId uniqueness PER gateway). Both must be processed — neither is a replay of the other.
        vm.prank(address(gateway));
        link.receiveMessage(RECEIVE_ID, counterpart, _payload());
        vm.prank(address(gateway2));
        link.receiveMessage(RECEIVE_ID, counterpart2, _payload());

        assertEq(handler.calls(), 2, "cross-gateway same-id messages both processed");
    }

    function test_ReceiveMessageNoHandlerReverts() public {
        vm.prank(admin);
        link.setLink(address(gateway), counterpart, false); // link but no handler

        vm.prank(address(gateway));
        vm.expectRevert(abi.encodeWithSelector(ICrosschainLink.CrosschainHandlerNotRegistered.selector, TAG));
        link.receiveMessage(RECEIVE_ID, counterpart, _payload());
    }

    function test_ReceiveMessageInvalidPayloadReverts() public {
        _register();
        vm.prank(address(gateway));
        vm.expectRevert(ICrosschainLink.CrosschainInvalidPayload.selector);
        link.receiveMessage(RECEIVE_ID, counterpart, hex"1122"); // < 4 bytes
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               SEND MESSAGE
    //////////////////////////////////////////////////////////////////////////*//

    function test_SendMessageByAdmin() public {
        _register();
        bytes memory payload = _payload();
        vm.prank(admin);
        bytes32 id = link.sendMessage(chainOnly, payload, new bytes[](0));

        assertEq(id, gateway.SEND_ID());
        assertEq(gateway.lastRecipient(), counterpart);
        assertEq(gateway.lastPayload(), payload);
    }

    function test_SendMessageRevertsNonAdmin() public {
        _register();
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        link.sendMessage(chainOnly, _payload(), new bytes[](0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsInterfaceCrosschainLink() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(ICrosschainLink).interfaceId));
    }
}
