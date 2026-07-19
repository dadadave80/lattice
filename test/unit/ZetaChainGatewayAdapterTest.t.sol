// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ZetaChainGatewayAdapterTestBase} from "@lattice-test/base/ZetaChainGatewayAdapterTestBase.sol";
import {ZetaChainGatewayAdapter} from "@lattice/crosschain/ZetaChainGatewayAdapter.sol";
import {IZetaChainGatewayAdapter} from "@lattice/interfaces/crosschain/IZetaChainGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {IGatewayEVM, MessageContext, RevertOptions} from "@lattice/interfaces/external/zetachain/IGatewayEVM.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @notice Minimal ZetaChain `GatewayEVM` mock. `call` records `(receiver, payload)` + the revert address / gas /
///         forwarded value the outbound test asserts on. The harness drives inbound delivery by pranking AS this
///         gateway (passed as the adapter's ctor arg) and handing `onCall` a settable `MessageContext.sender`.
contract MockGatewayEVM is IGatewayEVM {
    address public lastReceiver;
    bytes public lastPayload;
    address public lastRevertAddress;
    bool public lastCallOnRevert;
    uint256 public lastOnRevertGasLimit;
    uint256 public lastValue;
    uint256 public calls;

    function call(address receiver, bytes calldata payload, RevertOptions calldata revertOptions) external payable {
        lastReceiver = receiver;
        lastPayload = payload;
        lastRevertAddress = revertOptions.revertAddress;
        lastCallOnRevert = revertOptions.callOnRevert;
        lastOnRevertGasLimit = revertOptions.onRevertGasLimit;
        lastValue = msg.value;
        ++calls;
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

contract ZetaChainGatewayAdapterTest is ZetaChainGatewayAdapterTestBase {
    MockGatewayEVM gateway;
    MockRecipient recipient;

    address admin = address(0x1);
    address user = address(0x2);
    address remoteApp = address(0xA11CE); // the trusted ZEVM universal app (hub) for REMOTE_CHAIN
    address finalRecipient = address(0xCAFE);
    address remoteSender = address(0x5151); // the origin EOA/contract on REMOTE_CHAIN

    uint256 constant REMOTE_CHAIN = 7000; // ZetaChain-ish hub chainId
    uint256 constant DEFAULT_REVERT_GAS = 200_000;

    bytes recip; // dest recipient (ERC-7930)
    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        gateway = new MockGatewayEVM();

        // Register the hub route (REMOTE_CHAIN => remoteApp) at init in BOTH maps.
        diamond = _deployZetaChainGatewayAdapter(admin, address(gateway), REMOTE_CHAIN, remoteApp, DEFAULT_REVERT_GAS);
        adapter = ZetaChainGatewayAdapter(payable(diamond));
        recipient = new MockRecipient();

        recip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, finalRecipient);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_Gateway() public view {
        assertEq(adapter.gateway(), address(gateway));
    }

    function test_DefaultOnRevertGasLimit() public view {
        assertEq(adapter.defaultOnRevertGasLimit(), DEFAULT_REVERT_GAS);
    }

    function test_HubRouteRegisteredBothMaps() public view {
        assertEq(adapter.getRemoteApp(REMOTE_CHAIN), remoteApp, "forward map");
        assertEq(adapter.getChainIdForApp(remoteApp), REMOTE_CHAIN, "reverse map");
    }

    function test_SetGateway() public {
        address newGateway = address(0xBEEF);
        vm.prank(admin);
        adapter.setGateway(newGateway);
        assertEq(adapter.gateway(), newGateway);
    }

    function test_SetGatewayRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.setGateway(address(0xBEEF));
    }

    function test_SetGatewayRejectsZero() public {
        vm.prank(admin);
        vm.expectRevert(IZetaChainGatewayAdapter.InvalidGateway.selector);
        adapter.setGateway(address(0));
    }

    function test_RegisterRemote() public {
        vm.prank(admin);
        adapter.registerRemote(9000, address(0xD00D));
        assertEq(adapter.getRemoteApp(9000), address(0xD00D));
        assertEq(adapter.getChainIdForApp(address(0xD00D)), 9000);
    }

    function test_RegisterRemoteRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerRemote(9000, address(0xD00D));
    }

    function test_RegisterRemoteRejectsZero() public {
        vm.prank(admin);
        vm.expectRevert(IZetaChainGatewayAdapter.InvalidRemote.selector);
        adapter.registerRemote(9000, address(0));
    }

    /// @notice Hardening: chain 0 (the reverse-map "unregistered" sentinel) is rejected as a source chainId.
    function test_RegisterRemoteRejectsZeroChainId() public {
        vm.prank(admin);
        vm.expectRevert(IZetaChainGatewayAdapter.InvalidRemote.selector);
        adapter.registerRemote(0, address(0xD00D));
    }

    function test_RegisterRemoteDuplicateChainReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IZetaChainGatewayAdapter.RemoteAlreadyRegistered.selector, REMOTE_CHAIN));
        adapter.registerRemote(REMOTE_CHAIN, address(0xD00D));
    }

    function test_RegisterRemoteDuplicateAppReverts() public {
        // remoteApp is already mapped to REMOTE_CHAIN (reverse map); reusing it for a new chain must revert.
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IZetaChainGatewayAdapter.RemoteAlreadyRegistered.selector, 9000));
        adapter.registerRemote(9000, remoteApp);
    }

    function test_SetDefaultOnRevertGasLimit() public {
        vm.prank(admin);
        adapter.setDefaultOnRevertGasLimit(500_000);
        assertEq(adapter.defaultOnRevertGasLimit(), 500_000);
    }

    function test_SetDefaultOnRevertGasLimitRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.setDefaultOnRevertGasLimit(500_000);
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

    function _envelope(address sender, bytes memory payload, uint256 nonce) internal view returns (bytes memory) {
        return abi.encode(InteroperableAddress.formatEvmV1(block.chainid, sender), recip, payload, nonce);
    }

    function test_SendSubmitsToGateway() public {
        vm.prank(user);
        bytes32 id = adapter.sendMessage(recip, hex"deadbeef", new bytes[](0));

        assertEq(id, keccak256(abi.encode(block.chainid, uint256(0))), "id = keccak(chainid, nonce)");
        assertEq(gateway.calls(), 1);
        assertEq(gateway.lastReceiver(), remoteApp, "receiver = trusted ZEVM universal app (hub)");
        // First outbound uses nonce 0 (the source-minted monotonic counter).
        assertEq(
            gateway.lastPayload(), _envelope(user, hex"deadbeef", 0), "wire envelope = (sender, recip, payload, nonce)"
        );
        assertEq(gateway.lastRevertAddress(), user, "default RevertOptions.revertAddress = msg.sender");
        assertFalse(gateway.lastCallOnRevert(), "default RevertOptions.callOnRevert = false");
        assertEq(gateway.lastOnRevertGasLimit(), DEFAULT_REVERT_GAS, "default RevertOptions.onRevertGasLimit");
    }

    function test_SendForwardsValueAsFee() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        adapter.sendMessage{value: 0.3 ether}(recip, hex"01", new bytes[](0));
        assertEq(gateway.lastValue(), 0.3 ether, "msg.value forwarded as the native messaging fee");
    }

    function test_SendMonotonicNonce() public {
        vm.startPrank(user);
        bytes32 id0 = adapter.sendMessage(recip, hex"01", new bytes[](0));
        bytes32 id1 = adapter.sendMessage(recip, hex"01", new bytes[](0)); // identical content
        vm.stopPrank();
        assertTrue(id0 != id1, "monotonic nonce => distinct ids for identical content");
        assertEq(id0, keccak256(abi.encode(block.chainid, uint256(0))));
        assertEq(id1, keccak256(abi.encode(block.chainid, uint256(1))));
    }

    function test_SendEmitsMessageSent() public {
        vm.prank(user);
        vm.expectEmit(false, false, false, false);
        emit IERC7786GatewaySource.MessageSent(bytes32(0), "", "", "", 0, new bytes[](0));
        adapter.sendMessage(recip, hex"deadbeef", new bytes[](0));
    }

    function test_SendUnknownDestinationReverts() public {
        bytes memory unknown = InteroperableAddress.formatEvmV1(999, finalRecipient);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IZetaChainGatewayAdapter.UnknownDestinationChain.selector, 999));
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

    function _message(bytes memory payload, uint256 nonce) internal view returns (bytes memory) {
        return abi.encode(_senderInterop(), _localRecip(), payload, nonce);
    }

    function _ctx(address sender) internal pure returns (MessageContext memory) {
        return MessageContext({sender: sender});
    }

    function _expectedId(uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(REMOTE_CHAIN, nonce));
    }

    /// @notice Hardening (adversarial finding): reject a message whose envelope self-declares a source chain that
    ///         differs from the chain registered for the delivering ZEVM app (a shared/misconfigured app fronting
    ///         the wrong corridor) — fail-closed rather than misattribute into a colliding id namespace.
    function test_ReceiveSourceChainMismatchReverts() public {
        bytes memory mismatched =
            abi.encode(InteroperableAddress.formatEvmV1(9999, remoteSender), _localRecip(), hex"01", uint256(0));
        vm.prank(address(gateway));
        vm.expectRevert(
            abi.encodeWithSelector(IZetaChainGatewayAdapter.SourceChainMismatch.selector, uint256(9999), REMOTE_CHAIN)
        );
        adapter.onCall(_ctx(remoteApp), mismatched);
    }

    function test_ReceiveDeliversToRecipient() public {
        vm.prank(address(gateway));
        adapter.onCall(_ctx(remoteApp), _message(hex"c0ffee", 0));

        assertEq(recipient.calls(), 1);
        assertEq(recipient.lastReceiveId(), _expectedId(0), "receiveId = (source, nonce) id");
        assertEq(recipient.lastPayload(), hex"c0ffee");
        assertEq(recipient.lastSender(), _senderInterop());
    }

    function test_ReceiveReplayReverts() public {
        vm.startPrank(address(gateway));
        adapter.onCall(_ctx(remoteApp), _message(hex"01", 5));
        vm.expectRevert(
            abi.encodeWithSelector(
                IZetaChainGatewayAdapter.MessageAlreadyExecuted.selector, REMOTE_CHAIN, _expectedId(5)
            )
        );
        adapter.onCall(_ctx(remoteApp), _message(hex"01", 5)); // same nonce = same id = replay
        vm.stopPrank();
    }

    /// @notice Regression for the adversarial finding: two byte-identical messages carrying DISTINCT source nonces
    ///         must BOTH deliver with DISTINCT ids — content-keyed dedup would permanently drop the second and hand
    ///         the recipient a non-unique id.
    function test_ReceiveDuplicateContentDistinctNoncesBothDeliver() public {
        vm.startPrank(address(gateway));
        adapter.onCall(_ctx(remoteApp), _message(hex"01", 1));
        bytes32 id1 = recipient.lastReceiveId();
        adapter.onCall(_ctx(remoteApp), _message(hex"01", 2)); // identical content, different nonce
        bytes32 id2 = recipient.lastReceiveId();
        vm.stopPrank();

        assertEq(recipient.calls(), 2, "both identical-content messages delivered");
        assertTrue(id1 != id2, "distinct ids for distinct nonces");
        assertEq(id1, _expectedId(1));
        assertEq(id2, _expectedId(2));
    }

    function test_ReceiveWrongGatewayReverts() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IZetaChainGatewayAdapter.NotGateway.selector, user));
        adapter.onCall(_ctx(remoteApp), _message(hex"01", 0));
    }

    function test_ReceiveUnregisteredAppReverts() public {
        // context.sender is not a registered trusted ZEVM universal app.
        address rogue = address(0xDEAD);
        vm.prank(address(gateway));
        vm.expectRevert(abi.encodeWithSelector(IZetaChainGatewayAdapter.InvalidOriginApp.selector, rogue));
        adapter.onCall(_ctx(rogue), _message(hex"01", 0));
    }

    function test_ReceiveWrongDestinationChainReverts() public {
        // recipient targets REMOTE_CHAIN, not THIS chain.
        bytes memory wrongChainRecip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(recipient));
        bytes memory message = abi.encode(_senderInterop(), wrongChainRecip, hex"01", uint256(0));
        vm.prank(address(gateway));
        vm.expectRevert(abi.encodeWithSelector(IZetaChainGatewayAdapter.WrongDestinationChain.selector, REMOTE_CHAIN));
        adapter.onCall(_ctx(remoteApp), message);
    }
}
