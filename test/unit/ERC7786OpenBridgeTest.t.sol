// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ERC7786OpenBridgeTestBase} from "@lattice-test/base/ERC7786OpenBridgeTestBase.sol";
import {ERC7786OpenBridge} from "@lattice/crosschain/ERC7786OpenBridge.sol";
import {IERC7786OpenBridge} from "@lattice/interfaces/crosschain/IERC7786OpenBridge.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @notice A source gateway used both as a fan-out target (sendMessage) and an attester (its address).
contract MockSourceGateway is IERC7786GatewaySource {
    bytes public lastRecipient;
    bytes public lastPayload;
    uint256 internal _n;

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
        return bytes32(++_n);
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

contract ERC7786OpenBridgeTest is ERC7786OpenBridgeTestBase {
    MockSourceGateway g1;
    MockSourceGateway g2;
    MockRecipient recipient;

    address admin = address(0x1);
    address user = address(0x2);
    address remoteBridgeAddr = address(0xB0B);

    uint256 constant REMOTE_CHAIN = 10;
    bytes remoteBridge; // full interop of the matching bridge on REMOTE_CHAIN
    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        diamond = _deployERC7786OpenBridge(admin);
        bridge = ERC7786OpenBridge(payable(diamond));
        g1 = new MockSourceGateway();
        g2 = new MockSourceGateway();
        recipient = new MockRecipient();

        remoteBridge = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, remoteBridgeAddr);

        vm.startPrank(admin);
        bridge.addGateway(address(g1));
        bridge.addGateway(address(g2));
        bridge.setThreshold(2);
        bridge.registerRemoteBridge(remoteBridge);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_Config() public view {
        assertEq(bridge.getGateways().length, 2);
        assertEq(bridge.getThreshold(), 2);
        assertEq(bridge.getRemoteBridge(InteroperableAddress.formatEvmV1(REMOTE_CHAIN)), remoteBridge);
    }

    function test_SetThresholdZeroReverts() public {
        vm.prank(admin);
        vm.expectRevert(IERC7786OpenBridge.ThresholdViolation.selector);
        bridge.setThreshold(0);
    }

    function test_SetThresholdAboveGatewaysReverts() public {
        vm.prank(admin);
        vm.expectRevert(IERC7786OpenBridge.ThresholdViolation.selector);
        bridge.setThreshold(3);
    }

    function test_RemoveGatewayBelowThresholdReverts() public {
        vm.prank(admin);
        vm.expectRevert(IERC7786OpenBridge.ThresholdViolation.selector);
        bridge.removeGateway(address(g1)); // would leave 1 gateway < threshold 2
    }

    function test_AddGatewayRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        bridge.addGateway(address(0xABCD));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               SEND (FAN-OUT)
    //////////////////////////////////////////////////////////////////////////*//

    function test_SendMessageFansOutToAllGateways() public {
        bytes memory recip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0xCAFE));
        bytes memory payload = hex"deadbeef";

        vm.prank(user);
        bridge.sendMessage(recip, payload, new bytes[](0));

        bytes memory wrapped =
            abi.encode(uint256(1), InteroperableAddress.formatEvmV1(block.chainid, user), recip, payload);
        // both gateways received the wrapped message addressed to the remote bridge
        assertEq(g1.lastRecipient(), remoteBridge);
        assertEq(g1.lastPayload(), wrapped);
        assertEq(g2.lastRecipient(), remoteBridge);
        assertEq(g2.lastPayload(), wrapped);
    }

    function test_SendMessageRejectsValue() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(IERC7786OpenBridge.UnsupportedNativeTransfer.selector);
        bridge.sendMessage{value: 1}(
            InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0xCAFE)), hex"01", new bytes[](0)
        );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            RECEIVE (N-OF-M)
    //////////////////////////////////////////////////////////////////////////*//

    function _inbound(bytes memory unwrapped) internal view returns (bytes memory) {
        bytes memory originalSender = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0x5151));
        bytes memory localRecip = InteroperableAddress.formatEvmV1(block.chainid, address(recipient));
        return abi.encode(uint256(7), originalSender, localRecip, unwrapped);
    }

    function test_ReceiveBelowThresholdDoesNotExecute() public {
        bytes memory payload = _inbound(hex"c0ffee");
        vm.prank(address(g1));
        bridge.receiveMessage(bytes32(0), remoteBridge, payload);
        assertEq(recipient.calls(), 0, "not delivered below threshold");
    }

    function test_ReceiveAtThresholdExecutesOnce() public {
        bytes memory payload = _inbound(hex"c0ffee");
        bytes32 id = keccak256(abi.encode(remoteBridge, payload));

        vm.prank(address(g1));
        bridge.receiveMessage(bytes32(0), remoteBridge, payload);
        vm.prank(address(g2));
        vm.expectEmit(true, false, false, false);
        emit IERC7786OpenBridge.ExecutionSuccess(id);
        bridge.receiveMessage(bytes32(0), remoteBridge, payload);

        assertEq(recipient.calls(), 1, "delivered once at threshold");
        assertEq(recipient.lastReceiveId(), id);
        assertEq(recipient.lastPayload(), hex"c0ffee");
    }

    function test_ReceiveDuplicateGatewayDoesNotDoubleCount() public {
        bytes memory payload = _inbound(hex"01");
        vm.startPrank(address(g1));
        bridge.receiveMessage(bytes32(0), remoteBridge, payload);
        bridge.receiveMessage(bytes32(0), remoteBridge, payload); // same gateway again
        vm.stopPrank();
        assertEq(recipient.calls(), 0, "same gateway cannot reach threshold alone");
    }

    function test_ReceiveInvalidSenderReverts() public {
        bytes memory notTheBridge = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0xDEAD));
        vm.prank(address(g1));
        vm.expectRevert(IERC7786OpenBridge.InvalidCrosschainSender.selector);
        bridge.receiveMessage(bytes32(0), notTheBridge, _inbound(hex"01"));
    }

    function test_SupportsInterfaceGatewaySource() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC7786GatewaySource).interfaceId));
    }
}
