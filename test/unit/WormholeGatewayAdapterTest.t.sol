// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {WormholeGatewayAdapter} from "@lattice/crosschain/WormholeGatewayAdapter.sol";
import {WormholeGatewayAdapterLib} from "@lattice/crosschain/libraries/WormholeGatewayAdapterLib.sol";
import {IWormholeGatewayAdapter} from "@lattice/interfaces/crosschain/IWormholeGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";
import {IERC7786Attributes} from "@lattice/interfaces/external/IERC7786Attributes.sol";
import {IWormholeRelayer} from "@lattice/interfaces/external/IWormholeRelayer.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Test} from "forge-std/Test.sol";

contract MockWormholeRelayer is IWormholeRelayer {
    uint16 public lastTargetChain;
    address public lastTarget;
    bytes public lastPayload;
    uint256 public lastReceiverValue;
    uint256 public lastGasLimit;
    address public lastRefund;
    uint64 public seq;

    function sendPayloadToEvm(
        uint16 targetChain,
        address target,
        bytes calldata payload,
        uint256 receiverValue,
        uint256 gasLimit,
        uint16,
        address refundAddress
    ) external payable returns (uint64) {
        lastTargetChain = targetChain;
        lastTarget = target;
        lastPayload = payload;
        lastReceiverValue = receiverValue;
        lastGasLimit = gasLimit;
        lastRefund = refundAddress;
        return ++seq;
    }

    function quoteEVMDeliveryPrice(uint16, uint256, uint256) external pure returns (uint256, uint256) {
        return (0.01 ether, 0);
    }
}

contract MockRecipient is IERC7786Recipient {
    bytes32 public lastReceiveId;
    bytes public lastSender;
    bytes public lastPayload;

    function receiveMessage(bytes32 receiveId, bytes calldata sender, bytes calldata payload)
        external
        payable
        returns (bytes4)
    {
        lastReceiveId = receiveId;
        lastSender = sender;
        lastPayload = payload;
        return IERC7786Recipient.receiveMessage.selector;
    }
}

contract MockWormholeAdapter is AccessControl, WormholeGatewayAdapter {
    function initialize(address admin_, address relayer_, uint16 chainId_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        WormholeGatewayAdapterLib.__WormholeGatewayAdapter_init(relayer_, chainId_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract WormholeGatewayAdapterTest is Test {
    MockWormholeAdapter adapter;
    MockWormholeRelayer relayer;
    MockRecipient recipient;

    address admin = address(0x1);
    address user = address(0x2);
    address remoteGw = address(0xA11CE);

    uint256 constant REMOTE_CHAIN = 10;
    uint16 constant REMOTE_WORMHOLE = 24;
    uint16 constant LOCAL_WORMHOLE = 2;

    bytes recip; // dest recipient (ERC-7930)
    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        relayer = new MockWormholeRelayer();
        adapter = new MockWormholeAdapter();
        adapter.initialize(admin, address(relayer), LOCAL_WORMHOLE);
        recipient = new MockRecipient();

        recip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0xCAFE));

        vm.startPrank(admin);
        adapter.registerChainEquivalence(REMOTE_CHAIN, REMOTE_WORMHOLE);
        adapter.registerRemoteGateway(REMOTE_CHAIN, remoteGw);
        vm.stopPrank();
    }

    function _attr(uint256 value, uint256 gas, address refund) internal pure returns (bytes[] memory a) {
        a = new bytes[](1);
        a[0] = abi.encodeWithSelector(IERC7786Attributes.requestRelay.selector, value, gas, refund);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterChainEquivalence() public view {
        assertEq(adapter.getWormholeChain(REMOTE_CHAIN), REMOTE_WORMHOLE);
        assertEq(adapter.getChainId(REMOTE_WORMHOLE), REMOTE_CHAIN);
    }

    function test_RegisterChainEquivalenceRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerChainEquivalence(99, 99);
    }

    function test_RegisterRemoteGateway() public view {
        assertEq(adapter.getRemoteGateway(REMOTE_CHAIN), remoteGw);
    }

    function test_SupportsAttribute() public view {
        assertTrue(adapter.supportsAttribute(IERC7786Attributes.requestRelay.selector));
        assertFalse(adapter.supportsAttribute(bytes4(0x12345678)));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               SEND (2-PHASE)
    //////////////////////////////////////////////////////////////////////////*//

    function test_SendMessageNoAttributeStoresPending() public {
        vm.prank(user);
        bytes32 sendId = adapter.sendMessage(recip, hex"deadbeef", new bytes[](0));

        assertTrue(sendId != bytes32(0), "non-zero pending id");
        assertEq(relayer.lastTargetChain(), 0, "relayer not called yet");
    }

    function test_RequestRelayDispatches() public {
        vm.prank(user);
        bytes32 sendId = adapter.sendMessage(recip, hex"deadbeef", new bytes[](0));

        vm.deal(user, 1 ether);
        vm.prank(user);
        adapter.requestRelay{value: 0.02 ether}(sendId, 200_000, user);

        assertEq(relayer.lastTargetChain(), REMOTE_WORMHOLE);
        assertEq(relayer.lastTarget(), remoteGw);
        assertEq(relayer.lastGasLimit(), 200_000);
        assertEq(relayer.lastRefund(), user);
    }

    function test_SendMessageWithAttributeImmediate() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        bytes32 sendId = adapter.sendMessage{value: 0.02 ether}(recip, hex"deadbeef", _attr(0, 200_000, user));

        assertEq(sendId, bytes32(0), "immediate returns 0");
        assertEq(relayer.lastTargetChain(), REMOTE_WORMHOLE);
        assertEq(relayer.lastTarget(), remoteGw);
    }

    function test_SendMessageDuplicateAttributeReverts() public {
        bytes[] memory two = new bytes[](2);
        two[0] = abi.encodeWithSelector(IERC7786Attributes.requestRelay.selector, uint256(0), uint256(1), user);
        two[1] = two[0];
        vm.prank(user);
        vm.expectRevert(IWormholeGatewayAdapter.DuplicatedAttribute.selector);
        adapter.sendMessage(recip, hex"01", two);
    }

    function test_RequestRelayUnknownReverts() public {
        bytes32 unknown = bytes32(uint256(999));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IWormholeGatewayAdapter.UnknownMessage.selector, unknown));
        adapter.requestRelay(unknown, 1, user);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            RECEIVE (DESTINATION)
    //////////////////////////////////////////////////////////////////////////*//

    function _inbound(bytes32 sendId, bytes memory payload) internal view returns (bytes memory) {
        bytes memory sender = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0x5151));
        bytes memory localRecip = InteroperableAddress.formatEvmV1(block.chainid, address(recipient));
        return abi.encode(sendId, sender, localRecip, payload);
    }

    function test_ReceiveDeliversToRecipient() public {
        bytes32 deliveryHash = keccak256("dh");
        bytes32 srcUniversal = bytes32(uint256(uint160(remoteGw)));
        vm.prank(address(relayer));
        adapter.receiveWormholeMessages(
            _inbound(bytes32(uint256(1)), hex"c0ffee"), new bytes[](0), srcUniversal, REMOTE_WORMHOLE, deliveryHash
        );

        assertEq(recipient.lastReceiveId(), deliveryHash);
        assertEq(recipient.lastPayload(), hex"c0ffee");
    }

    function test_ReceiveReplayReverts() public {
        bytes32 srcUniversal = bytes32(uint256(uint160(remoteGw)));
        bytes memory msg_ = _inbound(bytes32(uint256(1)), hex"01");
        vm.startPrank(address(relayer));
        adapter.receiveWormholeMessages(msg_, new bytes[](0), srcUniversal, REMOTE_WORMHOLE, keccak256("a"));
        vm.expectRevert(
            abi.encodeWithSelector(IWormholeGatewayAdapter.MessageAlreadyExecuted.selector, REMOTE_CHAIN, 1)
        );
        adapter.receiveWormholeMessages(msg_, new bytes[](0), srcUniversal, REMOTE_WORMHOLE, keccak256("b"));
        vm.stopPrank();
    }

    function test_ReceiveWrongRelayerReverts() public {
        bytes32 srcUniversal = bytes32(uint256(uint160(remoteGw)));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IWormholeGatewayAdapter.NotWormholeRelayer.selector, user));
        adapter.receiveWormholeMessages(
            _inbound(bytes32(uint256(1)), hex"01"), new bytes[](0), srcUniversal, REMOTE_WORMHOLE, keccak256("a")
        );
    }

    function test_ReceiveWrongOriginReverts() public {
        bytes32 wrong = bytes32(uint256(uint160(address(0xDEAD))));
        vm.prank(address(relayer));
        vm.expectRevert(
            abi.encodeWithSelector(IWormholeGatewayAdapter.InvalidOriginGateway.selector, REMOTE_WORMHOLE, wrong)
        );
        adapter.receiveWormholeMessages(
            _inbound(bytes32(uint256(1)), hex"01"), new bytes[](0), wrong, REMOTE_WORMHOLE, keccak256("a")
        );
    }

    function test_SupportsInterfaceGatewaySource() public view {
        assertTrue(adapter.supportsInterface(type(IERC7786GatewaySource).interfaceId));
    }
}
