// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {HyperlaneGatewayAdapterTestBase} from "@lattice-test/base/HyperlaneGatewayAdapterTestBase.sol";
import {MockMailbox} from "@lattice-test/mocks/MockMailbox.sol";
import {HyperlaneGatewayAdapter} from "@lattice/crosschain/HyperlaneGatewayAdapter.sol";
import {IHyperlaneGatewayAdapter} from "@lattice/interfaces/crosschain/IHyperlaneGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

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

contract HyperlaneGatewayAdapterTest is HyperlaneGatewayAdapterTestBase {
    MockMailbox mailbox;
    MockRecipient recipient;

    address admin = address(0x1);
    address user = address(0x2);
    address remoteGw = address(0xA11CE);
    address finalRecipient = address(0xCAFE);

    // Domain deliberately != chainId: Hyperlane domains USUALLY equal the EVM chainId but are never
    // guaranteed to — the adapter must route by the registered map, never by inference.
    uint256 constant REMOTE_CHAIN = 10;
    uint32 constant REMOTE_DOMAIN = 30_010;
    uint256 constant DEST_GAS = 250_000;
    uint256 constant DEFAULT_GAS = 200_000; // HyperlaneGatewayAdapterLib.DEFAULT_DESTINATION_GAS

    bytes32 trustedRemote; // trusted remote adapter as bytes32
    bytes recip; // dest recipient (ERC-7930)
    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        mailbox = new MockMailbox();
        diamond = _deployHyperlaneGatewayAdapter(admin, address(mailbox));
        adapter = HyperlaneGatewayAdapter(payable(diamond));
        recipient = new MockRecipient();

        trustedRemote = bytes32(uint256(uint160(remoteGw)));
        recip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, finalRecipient);

        vm.startPrank(admin);
        adapter.registerDomain(REMOTE_CHAIN, REMOTE_DOMAIN);
        adapter.registerRemote(REMOTE_CHAIN, trustedRemote);
        adapter.configureDestination(REMOTE_CHAIN, DEST_GAS);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterDomain() public view {
        assertEq(adapter.domainOf(REMOTE_CHAIN), REMOTE_DOMAIN);
        assertEq(adapter.chainIdOf(REMOTE_DOMAIN), REMOTE_CHAIN);
    }

    function test_RegisterDomainRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerDomain(99, 99);
    }

    /// @notice FAIL-LOUD identity admin: an already-mapped chainId reverts (never remapped).
    function test_RegisterDomainDuplicateChainIdReverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperlaneGatewayAdapter.HyperlaneDomainAlreadyRegistered.selector, REMOTE_CHAIN, uint32(1234)
            )
        );
        adapter.registerDomain(REMOTE_CHAIN, 1234);
    }

    /// @notice FAIL-LOUD identity admin: an already-mapped domain reverts too (both directions guarded).
    function test_RegisterDomainDuplicateDomainReverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperlaneGatewayAdapter.HyperlaneDomainAlreadyRegistered.selector, uint256(999), REMOTE_DOMAIN
            )
        );
        adapter.registerDomain(999, REMOTE_DOMAIN);
    }

    function test_RegisterDomainZeroDomainReverts() public {
        vm.prank(admin);
        vm.expectRevert(IHyperlaneGatewayAdapter.HyperlaneZeroDomain.selector);
        adapter.registerDomain(999, 0);
    }

    function test_RegisterRemote() public view {
        assertEq(adapter.trustedRemoteOf(REMOTE_CHAIN), trustedRemote);
    }

    /// @notice The trusted remote is a TUNABLE (unlike the chainId ⇄ domain identity): re-registering updates.
    function test_RegisterRemoteIsTunable() public {
        bytes32 updated = bytes32(uint256(0xBEEF));
        vm.prank(admin);
        adapter.registerRemote(REMOTE_CHAIN, updated);
        assertEq(adapter.trustedRemoteOf(REMOTE_CHAIN), updated);
    }

    function test_RegisterRemoteZeroReverts() public {
        vm.prank(admin);
        vm.expectRevert(IHyperlaneGatewayAdapter.HyperlaneZeroRemote.selector);
        adapter.registerRemote(REMOTE_CHAIN, bytes32(0));
    }

    function test_RegisterRemoteRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerRemote(REMOTE_CHAIN, bytes32(uint256(1)));
    }

    function test_ConfigureDestination() public view {
        assertEq(adapter.destGasLimitOf(REMOTE_CHAIN), DEST_GAS);
    }

    /// @notice The destination gas limit is a TUNABLE: re-configuring updates.
    function test_ConfigureDestinationIsTunable() public {
        vm.prank(admin);
        adapter.configureDestination(REMOTE_CHAIN, 555_555);
        assertEq(adapter.destGasLimitOf(REMOTE_CHAIN), 555_555);
    }

    function test_ConfigureDestinationRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.configureDestination(REMOTE_CHAIN, 1);
    }

    function test_Mailbox() public view {
        assertEq(adapter.mailbox(), address(mailbox));
    }

    function test_SupportsAttributeAlwaysFalse() public view {
        assertFalse(adapter.supportsAttribute(bytes4(0x12345678)));
        assertFalse(adapter.supportsAttribute(bytes4(0)));
    }

    function test_SupportsInterfaceGatewaySource() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC7786GatewaySource).interfaceId));
    }

    function test_SupportsInterfaceHyperlaneGatewayAdapter() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IHyperlaneGatewayAdapter).interfaceId));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    function _wireMessage(address sender, bytes memory inner, uint256 nonce) internal view returns (bytes memory) {
        return abi.encode(InteroperableAddress.formatEvmV1(block.chainid, sender), recip, inner, nonce);
    }

    function _expectedMetadata(uint256 gasLimit, address refund) internal pure returns (bytes memory) {
        // Hyperlane StandardHookMetadata variant 1: variant || msgValue || gasLimit || refundAddress.
        return abi.encodePacked(uint16(1), uint256(0), gasLimit, refund);
    }

    function _sendId(uint256 srcChainId, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(srcChainId, nonce));
    }

    function test_SendDispatchesToMailbox() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        bytes32 id = adapter.sendMessage{value: 0.01 ether}(recip, hex"deadbeef", new bytes[](0));

        assertEq(id, _sendId(block.chainid, 1), "sendId = keccak256(chainid, nonce)");
        assertEq(mailbox.lastDestinationDomain(), REMOTE_DOMAIN, "routes by REGISTERED domain, not chainId");
        assertEq(mailbox.lastRecipientAddress(), trustedRemote, "dispatch targets the trusted remote adapter");
        assertEq(mailbox.lastBody(), _wireMessage(user, hex"deadbeef", 1), "wire envelope carries the nonce");
        assertEq(mailbox.lastMetadata(), _expectedMetadata(DEST_GAS, user), "StandardHookMetadata exact packing");
        assertEq(mailbox.lastValue(), 0.01 ether, "msg.value forwarded");
    }

    /// @notice The whole msg.value is forwarded to the Mailbox — overpayment refunds are the default hook's
    ///         job (refundAddress = the sending user in the metadata), never the adapter's.
    function test_SendForwardsWholeValue() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        adapter.sendMessage{value: 0.05 ether}(recip, hex"01", new bytes[](0));
        assertEq(address(mailbox).balance, 0.05 ether, "mailbox got the whole value");
        assertEq(user.balance, 1 ether - 0.05 ether, "no adapter-side refund");
        assertEq(diamond.balance, 0, "nothing trapped in the diamond");
    }

    /// @notice An unset per-dest gas limit falls back to the documented adapter default (200k).
    function test_SendUsesDefaultGasWhenUnconfigured() public {
        vm.prank(admin);
        adapter.configureDestination(REMOTE_CHAIN, 0); // tunable back to unset
        vm.deal(user, 1 ether);
        vm.prank(user);
        adapter.sendMessage{value: 0.01 ether}(recip, hex"01", new bytes[](0));
        assertEq(mailbox.lastMetadata(), _expectedMetadata(DEFAULT_GAS, user), "default gas in metadata");
    }

    function test_SendNonceIncrements() public {
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        bytes32 first = adapter.sendMessage{value: 0.01 ether}(recip, hex"01", new bytes[](0));
        bytes32 second = adapter.sendMessage{value: 0.01 ether}(recip, hex"01", new bytes[](0));
        vm.stopPrank();
        assertEq(first, _sendId(block.chainid, 1));
        assertEq(second, _sendId(block.chainid, 2), "byte-identical messages still get distinct sendIds");
    }

    function test_SendEmitsMessageSentAndDispatched() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit IHyperlaneGatewayAdapter.HyperlaneMessageDispatched(
            _sendId(block.chainid, 1), keccak256(abi.encode("hyperlane-msg", uint256(1))), REMOTE_DOMAIN
        );
        vm.expectEmit(true, false, false, false);
        emit IERC7786GatewaySource.MessageSent(_sendId(block.chainid, 1), "", "", "", 0, new bytes[](0));
        adapter.sendMessage{value: 0.01 ether}(recip, hex"deadbeef", new bytes[](0));
    }

    function test_SendInsufficientFeeReverts() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IHyperlaneGatewayAdapter.HyperlaneInsufficientFee.selector, 0.001 ether, 0.01 ether)
        );
        adapter.sendMessage{value: 0.001 ether}(recip, hex"01", new bytes[](0));
    }

    function test_SendUnknownDestinationReverts() public {
        bytes memory unknown = InteroperableAddress.formatEvmV1(999, finalRecipient);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IHyperlaneGatewayAdapter.HyperlaneUnknownDestinationChain.selector, 999));
        adapter.sendMessage(unknown, hex"01", new bytes[](0));
    }

    /// @notice A domain registered without its trusted remote is still an unknown destination (fail-closed).
    function test_SendUnsetRemoteReverts() public {
        vm.prank(admin);
        adapter.registerDomain(77, 7777); // remote intentionally left unset
        bytes memory dest = InteroperableAddress.formatEvmV1(77, finalRecipient);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IHyperlaneGatewayAdapter.HyperlaneUnknownDestinationChain.selector, 77));
        adapter.sendMessage(dest, hex"01", new bytes[](0));
    }

    function test_SendRejectsAttributes() public {
        bytes[] memory attrs = new bytes[](1);
        attrs[0] = abi.encodeWithSelector(bytes4(0xaabbccdd));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC7786GatewaySource.UnsupportedAttribute.selector, bytes4(0xaabbccdd)));
        adapter.sendMessage(recip, hex"01", attrs);
    }

    function test_SendMalformedRecipientReverts() public {
        vm.prank(user);
        vm.expectRevert(); // ERC-7930 parser rejects an empty/truncated recipient
        adapter.sendMessage(hex"", hex"01", new bytes[](0));
    }

    function test_QuoteFee() public view {
        assertEq(adapter.quoteFee(recip, hex"deadbeef"), 0.01 ether);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECEIVE
    //////////////////////////////////////////////////////////////////////////*//

    function _inboundMessage(bytes memory inner, uint256 nonce) internal view returns (bytes memory) {
        bytes memory senderInterop = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0x5151));
        bytes memory localRecip = InteroperableAddress.formatEvmV1(block.chainid, address(recipient));
        return abi.encode(senderInterop, localRecip, inner, nonce);
    }

    /// @notice Happy path through the mock's `process` driver — the Mailbox-invoked `handle` path end to end.
    function test_HandleDeliversToRecipient() public {
        mailbox.process(REMOTE_DOMAIN, trustedRemote, diamond, _inboundMessage(hex"c0ffee", 7));

        assertEq(recipient.calls(), 1);
        assertEq(recipient.lastReceiveId(), _sendId(REMOTE_CHAIN, 7), "receiveId = keccak256(srcChainId, nonce)");
        assertEq(recipient.lastPayload(), hex"c0ffee");
        assertEq(recipient.lastSender(), InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0x5151)));
    }

    /// @notice Suite-level dedup (defense-in-depth over the Mailbox's own `delivered` guard): a second
    ///         delivery of the same envelope reverts. Driven by pranking the mailbox directly because the
    ///         mock's `process` mirrors the upstream one-shot guard and would revert first (see below).
    function test_HandleReplayReverts() public {
        vm.startPrank(address(mailbox));
        adapter.handle(REMOTE_DOMAIN, trustedRemote, _inboundMessage(hex"01", 7));
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperlaneGatewayAdapter.HyperlaneMessageAlreadyExecuted.selector,
                REMOTE_CHAIN,
                _sendId(REMOTE_CHAIN, 7)
            )
        );
        adapter.handle(REMOTE_DOMAIN, trustedRemote, _inboundMessage(hex"01", 7));
        vm.stopPrank();
    }

    /// @notice The PROTOCOL-level replay guard: the Mailbox itself never redelivers a processed messageId.
    function test_MailboxRedeliveryRevertsBeforeAdapter() public {
        bytes memory message = _inboundMessage(hex"01", 8);
        mailbox.process(REMOTE_DOMAIN, trustedRemote, diamond, message);
        vm.expectRevert(bytes("Mailbox: already delivered"));
        mailbox.process(REMOTE_DOMAIN, trustedRemote, diamond, message);
    }

    function test_HandleNotMailboxReverts() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IHyperlaneGatewayAdapter.HyperlaneNotMailbox.selector, user));
        adapter.handle(REMOTE_DOMAIN, trustedRemote, _inboundMessage(hex"01", 1));
    }

    function test_HandleUntrustedSenderReverts() public {
        bytes32 wrongSender = bytes32(uint256(uint160(address(0xDEAD))));
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperlaneGatewayAdapter.HyperlaneInvalidOriginGateway.selector, REMOTE_DOMAIN, wrongSender
            )
        );
        mailbox.process(REMOTE_DOMAIN, wrongSender, diamond, _inboundMessage(hex"01", 1));
    }

    function test_HandleUnknownOriginReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperlaneGatewayAdapter.HyperlaneInvalidOriginGateway.selector, uint32(424_242), trustedRemote
            )
        );
        mailbox.process(424_242, trustedRemote, diamond, _inboundMessage(hex"01", 1));
    }

    /// @notice Hardening: a domain registered before its remote cannot satisfy auth via a zero sender.
    function test_HandleUnconfiguredRemoteReverts() public {
        vm.prank(admin);
        adapter.registerDomain(20, 30_200); // remote intentionally left unset
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperlaneGatewayAdapter.HyperlaneInvalidOriginGateway.selector, uint32(30_200), bytes32(0)
            )
        );
        mailbox.process(30_200, bytes32(0), diamond, _inboundMessage(hex"01", 1));
    }

    /// @notice `handle` is forced payable by IMessageRecipient, but the adapter never expects value-bearing
    ///         messages in v1 — stray value is rejected instead of being trapped in the Diamond.
    function test_HandleRejectsValue() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IHyperlaneGatewayAdapter.HyperlaneUnexpectedValue.selector, 1 wei));
        mailbox.process{value: 1 wei}(REMOTE_DOMAIN, trustedRemote, diamond, _inboundMessage(hex"01", 1));
    }

    /// @notice Hardening: a message whose recipient targets a different chain than this one is rejected
    ///         (defense-in-depth against a rogue/misconfigured trusted remote misdirecting delivery).
    function test_HandleWrongDestinationChainReverts() public {
        bytes memory senderInterop = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0x5151));
        bytes memory wrongChainRecip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(recipient));
        bytes memory message = abi.encode(senderInterop, wrongChainRecip, hex"01", uint256(1));
        vm.expectRevert(
            abi.encodeWithSelector(IHyperlaneGatewayAdapter.HyperlaneWrongDestinationChain.selector, REMOTE_CHAIN)
        );
        mailbox.process(REMOTE_DOMAIN, trustedRemote, diamond, message);
    }
}
