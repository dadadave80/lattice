// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {HyperbridgeGatewayAdapterTestBase} from "@lattice-test/base/HyperbridgeGatewayAdapterTestBase.sol";
import {MockIsmpHost} from "@lattice-test/mocks/MockIsmpHost.sol";
import {ChainRegistry} from "@lattice/crosschain/ChainRegistry.sol";
import {HyperbridgeGatewayAdapter} from "@lattice/crosschain/HyperbridgeGatewayAdapter.sol";
import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {IHyperbridgeGatewayAdapter} from "@lattice/interfaces/crosschain/IHyperbridgeGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {IncomingPostRequest, PostRequest} from "@lattice/interfaces/external/hyperbridge/IIsmpDispatcher.sol";
import {
    GetRequest,
    IncomingGetResponse,
    IncomingPostResponse,
    PostResponse
} from "@lattice/interfaces/external/hyperbridge/IIsmpModule.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @notice Minimal stablecoin-like ERC-20 (mint/approve/transfer/transferFrom) standing in for the host's
///         `feeToken`.
contract MockFeeToken is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function name() external pure returns (string memory) {
        return "Hyperbridge Fee Token";
    }

    function symbol() external pure returns (string memory) {
        return "FEE";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }
}

/// @notice CrosschainLink-style ERC-7786 recipient recording every delivery.
contract MockHyperbridgeRecipient is IERC7786Recipient {
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

contract HyperbridgeGatewayAdapterTest is HyperbridgeGatewayAdapterTestBase {
    MockIsmpHost host;
    MockFeeToken feeToken;
    MockHyperbridgeRecipient recipient;

    address admin = address(0x1);
    address user = address(0x2);
    address relayer = address(0x3);
    address finalRecipient = address(0xCAFE);
    address remoteSender = address(0x5151);

    // Base mainnet as the remote corridor: state machine id derived as bytes("EVM-8453").
    uint256 constant REMOTE_CHAIN = 8453;
    bytes constant REMOTE_SM_ID = bytes("EVM-8453"); // hand-built — the canonical derivation target
    uint64 constant DEST_TIMEOUT = 86_400;
    uint256 constant PER_BYTE_FEE = 11;
    uint256 constant RELAYER_FEE = 1e15;
    uint256 constant USER_FUNDS = 10 ether;

    // Substrate-style raw corridor (local routing handle 3367 — never a real EVM chainId).
    uint256 constant POLKADOT_HANDLE = 3367;
    bytes constant POLKADOT_SM_ID = bytes("POLKADOT-3367");

    bytes remoteModule; // trusted counterpart adapter module on the remote chain
    bytes recip; // dest recipient (ERC-7930)
    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        feeToken = new MockFeeToken();
        host = new MockIsmpHost(address(feeToken), PER_BYTE_FEE);
        diamond = _deployHyperbridgeGatewayAdapter(admin, address(host));
        adapter = HyperbridgeGatewayAdapter(payable(diamond));
        recipient = new MockHyperbridgeRecipient();

        remoteModule = abi.encodePacked(address(0xA11CE));
        recip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, finalRecipient);

        vm.startPrank(admin);
        adapter.registerStateMachine(REMOTE_CHAIN);
        adapter.registerRemoteModule(REMOTE_CHAIN, remoteModule);
        adapter.configureDestinationTimeout(REMOTE_CHAIN, DEST_TIMEOUT);
        vm.stopPrank();

        feeToken.mint(user, USER_FUNDS);
        vm.prank(user);
        feeToken.approve(diamond, type(uint256).max);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    function _envelope(address sender, bytes memory inner, uint256 nonce) internal view returns (bytes memory) {
        return abi.encode(InteroperableAddress.formatEvmV1(block.chainid, sender), recip, inner, nonce);
    }

    function _sendId(uint256 srcChainId, uint256 nonce) internal pure returns (bytes32) {
        return keccak256(abi.encode(srcChainId, nonce));
    }

    function _total(bytes memory envelope, uint256 relayerFee) internal pure returns (uint256) {
        return PER_BYTE_FEE * envelope.length + relayerFee;
    }

    /// @dev An inbound PostRequest from the Base corridor delivering `inner` to `recipient` on this chain.
    function _inboundRequest(bytes memory inner, uint256 envelopeNonce, uint64 protocolNonce)
        internal
        view
        returns (PostRequest memory)
    {
        bytes memory senderInterop = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, remoteSender);
        bytes memory localRecip = InteroperableAddress.formatEvmV1(block.chainid, address(recipient));
        return PostRequest({
            source: REMOTE_SM_ID,
            dest: bytes("EVM-31337"),
            nonce: protocolNonce,
            from: remoteModule,
            to: abi.encodePacked(diamond),
            timeoutTimestamp: 0,
            body: abi.encode(senderInterop, localRecip, inner, envelopeNonce)
        });
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The state machine id is DERIVED internally as `bytes("EVM-" + chainId)` — asserted against the
    ///         hand-built canonical bytes.
    function test_RegisterStateMachineDerivesCanonicalId() public view {
        assertEq(adapter.stateMachineIdOf(REMOTE_CHAIN), REMOTE_SM_ID, "derived EVM state machine id");
        assertEq(adapter.chainIdOfStateMachine(REMOTE_SM_ID), REMOTE_CHAIN, "reverse map by id bytes");
    }

    function test_RegisterStateMachineRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerStateMachine(99);
    }

    /// @notice FAIL-LOUD identity admin: an already-mapped chainId reverts (never remapped).
    function test_RegisterStateMachineDuplicateChainIdReverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperbridgeGatewayAdapter.HyperbridgeStateMachineAlreadyRegistered.selector, REMOTE_CHAIN, REMOTE_SM_ID
            )
        );
        adapter.registerStateMachine(REMOTE_CHAIN);
    }

    /// @notice FAIL-LOUD identity admin: an already-mapped state machine id reverts too (both directions,
    ///         via the keccak reverse map) — even when claimed through the RAW registration path.
    function test_RegisterStateMachineRawDuplicateIdReverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperbridgeGatewayAdapter.HyperbridgeStateMachineAlreadyRegistered.selector, uint256(999), REMOTE_SM_ID
            )
        );
        adapter.registerStateMachineRaw(999, REMOTE_SM_ID);
    }

    function test_RegisterStateMachineRawDuplicateChainIdReverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperbridgeGatewayAdapter.HyperbridgeStateMachineAlreadyRegistered.selector,
                REMOTE_CHAIN,
                POLKADOT_SM_ID
            )
        );
        adapter.registerStateMachineRaw(REMOTE_CHAIN, POLKADOT_SM_ID);
    }

    function test_RegisterStateMachineZeroChainIdReverts() public {
        vm.startPrank(admin);
        vm.expectRevert(IHyperbridgeGatewayAdapter.HyperbridgeZeroChainId.selector);
        adapter.registerStateMachine(0);
        vm.expectRevert(IHyperbridgeGatewayAdapter.HyperbridgeZeroChainId.selector);
        adapter.registerStateMachineRaw(0, POLKADOT_SM_ID);
        vm.stopPrank();
    }

    function test_RegisterStateMachineRawEmptyIdReverts() public {
        vm.prank(admin);
        vm.expectRevert(IHyperbridgeGatewayAdapter.HyperbridgeEmptyStateMachineId.selector);
        adapter.registerStateMachineRaw(999, "");
    }

    function test_RegisterStateMachineRawRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerStateMachineRaw(POLKADOT_HANDLE, POLKADOT_SM_ID);
    }

    function test_RegisterRemoteModule() public view {
        assertEq(adapter.hyperbridgeRemoteModuleOf(REMOTE_CHAIN), remoteModule);
    }

    /// @notice The trusted remote module is a TUNABLE (unlike the state machine identity): re-registering
    ///         updates.
    function test_RegisterRemoteModuleIsTunable() public {
        bytes memory updated = abi.encodePacked(address(0xBEEF));
        vm.prank(admin);
        adapter.registerRemoteModule(REMOTE_CHAIN, updated);
        assertEq(adapter.hyperbridgeRemoteModuleOf(REMOTE_CHAIN), updated);
    }

    function test_RegisterRemoteModuleEmptyReverts() public {
        vm.prank(admin);
        vm.expectRevert(IHyperbridgeGatewayAdapter.HyperbridgeEmptyRemoteModule.selector);
        adapter.registerRemoteModule(REMOTE_CHAIN, "");
    }

    function test_RegisterRemoteModuleRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerRemoteModule(REMOTE_CHAIN, remoteModule);
    }

    function test_ConfigureDestinationTimeout() public view {
        assertEq(adapter.hyperbridgeDestTimeoutOf(REMOTE_CHAIN), DEST_TIMEOUT);
    }

    /// @notice The destination timeout is a TUNABLE: re-configuring updates (0 = host default handling).
    function test_ConfigureDestinationTimeoutIsTunable() public {
        vm.prank(admin);
        adapter.configureDestinationTimeout(REMOTE_CHAIN, 0);
        assertEq(adapter.hyperbridgeDestTimeoutOf(REMOTE_CHAIN), 0);
    }

    function test_ConfigureDestinationTimeoutRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.configureDestinationTimeout(REMOTE_CHAIN, 1);
    }

    function test_IsmpHost() public view {
        assertEq(adapter.ismpHost(), address(host));
    }

    /// @notice The fee token is read LIVE from the host — a host-side migration is visible immediately (the
    ///         adapter never caches it).
    function test_FeeTokenReadLive() public {
        assertEq(adapter.hyperbridgeFeeToken(), address(feeToken));
        MockFeeToken migrated = new MockFeeToken();
        host.setFeeToken(address(migrated));
        assertEq(adapter.hyperbridgeFeeToken(), address(migrated), "live passthrough, never cached");
    }

    function test_SupportsAttributeAlwaysFalse() public view {
        assertFalse(adapter.supportsAttribute(bytes4(0x12345678)));
        assertFalse(adapter.supportsAttribute(bytes4(0)));
    }

    function test_SupportsInterfaceGatewaySource() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC7786GatewaySource).interfaceId));
    }

    function test_SupportsInterfaceHyperbridgeGatewayAdapter() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IHyperbridgeGatewayAdapter).interfaceId));
    }

    /// @dev Only `d.initialize` is wrapped in `expectRevert` (the `HyperbridgeZeroHost` revert bubbles up
    ///      through {Diamond.initialize}); `deployer` was created in `setUp`.
    function test_InitRejectsZeroHost() public {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, address(0));
        Diamond d = new Diamond();
        vm.expectRevert(IHyperbridgeGatewayAdapter.HyperbridgeZeroHost.selector);
        d.initialize(cuts, init, initCalldata);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Every DispatchPost field verbatim: dest = the HAND-BUILT `bytes("EVM-8453")`, to = the
    ///         registered module, timeout from config, fee = the relayer fee, and — REFUND REGRESSION —
    ///         payer = the pranked USER (a diamond payer would strand host-side timeout fee refunds).
    function test_SendWithFeeDispatchPostFieldsVerbatim() public {
        vm.prank(user);
        bytes32 id = adapter.sendMessageWithFee(recip, hex"deadbeef", RELAYER_FEE);

        assertEq(id, _sendId(block.chainid, 1), "sendId = keccak256(chainid, nonce)");
        assertEq(host.lastDest(), REMOTE_SM_ID, "dest = hand-built EVM-8453 state machine id");
        assertEq(host.lastTo(), remoteModule, "dispatch targets the trusted remote module");
        assertEq(host.lastBody(), _envelope(user, hex"deadbeef", 1), "wire envelope carries the nonce");
        assertEq(host.lastTimeout(), DEST_TIMEOUT, "per-dest timeout from config");
        assertEq(host.lastFee(), RELAYER_FEE, "relayer fee rides DispatchPost.fee");
        assertEq(host.lastPayer(), user, "REFUND-CRITICAL: payer is the USER, never the diamond");
        assertEq(host.lastValue(), 0, "no native value in v1");
    }

    /// @notice Exact fee-token accounting: user debited `perByteFee * body.length + relayerFee`, host credited
    ///         the same, NOTHING left on the diamond, and the host allowance reset to 0.
    function test_SendFeeTokenAccountingExact() public {
        uint256 total = _total(_envelope(user, hex"deadbeef", 1), RELAYER_FEE);
        vm.prank(user);
        adapter.sendMessageWithFee(recip, hex"deadbeef", RELAYER_FEE);

        assertEq(feeToken.balanceOf(user), USER_FUNDS - total, "user debited exactly total");
        assertEq(feeToken.balanceOf(address(host)), total, "host credited exactly total");
        assertEq(feeToken.balanceOf(diamond), 0, "nothing trapped in the diamond");
        assertEq(feeToken.allowance(diamond, address(host)), 0, "allowance reset to 0");
    }

    /// @notice The plain ERC-7786 `sendMessage` delegates with relayerFee = 0 (unfunded/self-relay — valid in
    ///         ISMP; the proof can still be relayed permissionlessly).
    function test_SendMessageDelegatesWithZeroRelayerFee() public {
        vm.prank(user);
        bytes32 id = adapter.sendMessage(recip, hex"c0ffee", new bytes[](0));
        assertEq(id, _sendId(block.chainid, 1));
        assertEq(host.lastFee(), 0, "relayerFee = 0 on the plain path");
        assertEq(host.lastPayer(), user, "payer still the user");
        assertEq(feeToken.balanceOf(address(host)), _total(_envelope(user, hex"c0ffee", 1), 0));
    }

    function test_SendNonceIncrements() public {
        vm.startPrank(user);
        bytes32 first = adapter.sendMessageWithFee(recip, hex"01", 0);
        bytes32 second = adapter.sendMessageWithFee(recip, hex"01", 0);
        vm.stopPrank();
        assertEq(first, _sendId(block.chainid, 1));
        assertEq(second, _sendId(block.chainid, 2), "byte-identical messages still get distinct sendIds");
    }

    function test_SendEmitsMessageSentAndDispatched() public {
        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit IHyperbridgeGatewayAdapter.HyperbridgeMessageDispatched(
            _sendId(block.chainid, 1), keccak256(abi.encode("ismp-commitment", uint256(1))), REMOTE_CHAIN
        );
        vm.expectEmit(true, false, false, true);
        emit IERC7786GatewaySource.MessageSent(
            _sendId(block.chainid, 1),
            InteroperableAddress.formatEvmV1(block.chainid, user),
            recip,
            hex"deadbeef",
            0,
            new bytes[](0)
        );
        adapter.sendMessageWithFee(recip, hex"deadbeef", RELAYER_FEE);
    }

    /// @notice Defensive delta-sweep: when the host under-pulls (settable on the mock), the leftover fee token
    ///         goes BACK to the user — never stranded on the diamond.
    function test_SendSweepsLeftoverWhenHostUnderPulls() public {
        uint256 shortfall = 37;
        host.setPullShortfall(shortfall);
        uint256 total = _total(_envelope(user, hex"deadbeef", 1), RELAYER_FEE);

        vm.prank(user);
        adapter.sendMessageWithFee(recip, hex"deadbeef", RELAYER_FEE);

        assertEq(feeToken.balanceOf(user), USER_FUNDS - total + shortfall, "leftover swept back to the user");
        assertEq(feeToken.balanceOf(address(host)), total - shortfall, "host got what it pulled");
        assertEq(feeToken.balanceOf(diamond), 0, "diamond zero after sweep");
        assertEq(feeToken.allowance(diamond, address(host)), 0, "allowance still reset");
    }

    /// @notice DELTA-SWEEP ISOLATION (review finding): a PRE-EXISTING diamond feeToken balance (e.g. other
    ///         modules' holdings in a combined diamond) must survive a send — under-pull included — untouched:
    ///         the sweep is snapshot-delta-based, never absolute.
    function test_SendPreservesPreExistingDiamondFeeTokenBalance() public {
        uint256 preExisting = 5 ether;
        feeToken.mint(diamond, preExisting);
        uint256 shortfall = 37;
        host.setPullShortfall(shortfall);
        uint256 total = _total(_envelope(user, hex"deadbeef", 1), RELAYER_FEE);

        vm.prank(user);
        adapter.sendMessageWithFee(recip, hex"deadbeef", RELAYER_FEE);

        assertEq(feeToken.balanceOf(diamond), preExisting, "pre-existing diamond balance untouched by the sweep");
        assertEq(feeToken.balanceOf(user), USER_FUNDS - total + shortfall, "user got exactly the shortfall back");
    }

    /// @notice EIP-170 CEILING GUARD (review finding): the ChainRegistry facet sits 262 B under the limit
    ///         after its 10th inlined fan-out lib — catch the overflow in CI, not at deploy. When this fails,
    ///         extract the addEvmChain fan-out into a dedicated ChainFanOut facet (planned split).
    function test_ChainRegistryFacetFitsEip170() public {
        assertLe(
            address(new ChainRegistry()).code.length, 24_576, "ChainRegistry facet exceeds EIP-170 - split the fan-out"
        );
    }

    function test_QuoteDispatchFeeMatchesCharge() public {
        uint256 quote = adapter.quoteDispatchFee(recip, hex"deadbeef", RELAYER_FEE);
        assertEq(quote, _total(_envelope(user, hex"deadbeef", 1), RELAYER_FEE), "quote = perByte * body + relayer");

        vm.prank(user);
        adapter.sendMessageWithFee(recip, hex"deadbeef", RELAYER_FEE);
        assertEq(feeToken.balanceOf(address(host)), quote, "the quote IS the charge (same body builder)");
    }

    /// @notice A host-side perByteFee migration is reflected in the next quote (read live, never cached).
    function test_QuoteReflectsPerByteFeeChange() public {
        uint256 before = adapter.quoteDispatchFee(recip, hex"deadbeef", 0);
        host.setPerByteFee(PER_BYTE_FEE * 3);
        assertEq(adapter.quoteDispatchFee(recip, hex"deadbeef", 0), before * 3, "per-byte part scales");
    }

    function test_SendUnknownDestinationReverts() public {
        bytes memory unknown = InteroperableAddress.formatEvmV1(999, finalRecipient);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IHyperbridgeGatewayAdapter.HyperbridgeUnknownDestinationChain.selector, 999)
        );
        adapter.sendMessageWithFee(unknown, hex"01", 0);
    }

    /// @notice A state machine registered without its trusted remote module is still an unknown destination
    ///         (fail-closed).
    function test_SendUnsetRemoteModuleReverts() public {
        vm.prank(admin);
        adapter.registerStateMachine(77); // remote module intentionally left unset
        bytes memory dest = InteroperableAddress.formatEvmV1(77, finalRecipient);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IHyperbridgeGatewayAdapter.HyperbridgeUnknownDestinationChain.selector, 77)
        );
        adapter.sendMessageWithFee(dest, hex"01", 0);
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
        adapter.sendMessageWithFee(hex"", hex"01", 0);
    }

    /// @notice Without a fee-token approval the pull fails LOUD — the adapter never dispatches unpaid.
    function test_SendWithoutApprovalReverts() public {
        vm.prank(user);
        feeToken.approve(diamond, 0);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IBridgeFungible.BridgeTransferFailed.selector, address(feeToken)));
        adapter.sendMessageWithFee(recip, hex"01", 0);
    }

    /// @notice The native-token fee path (host-side uniswap swap of msg.value) is DEFERRED (issue #77 Q13) —
    ///         stray value reverts instead of being trapped in the diamond.
    function test_SendRejectsNativeValue() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IHyperbridgeGatewayAdapter.HyperbridgeUnexpectedValue.selector, 1 wei));
        adapter.sendMessage{value: 1 wei}(recip, hex"01", new bytes[](0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECEIVE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Happy path through the mock's `deliverPostRequest` driver — the host-invoked `onAccept` path
    ///         end to end into a CrosschainLink-style recipient.
    function test_OnAcceptDeliversToRecipient() public {
        host.deliverPostRequest(diamond, _inboundRequest(hex"c0ffee", 7, 1), relayer);

        assertEq(recipient.calls(), 1);
        assertEq(recipient.lastReceiveId(), _sendId(REMOTE_CHAIN, 7), "receiveId = keccak256(srcChainId, nonce)");
        assertEq(recipient.lastPayload(), hex"c0ffee");
        assertEq(recipient.lastSender(), InteroperableAddress.formatEvmV1(REMOTE_CHAIN, remoteSender));
    }

    function test_OnAcceptNotHostReverts() public {
        PostRequest memory request = _inboundRequest(hex"01", 1, 1);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IHyperbridgeGatewayAdapter.HyperbridgeNotHost.selector, user));
        adapter.onAccept(IncomingPostRequest({request: request, relayer: relayer}));
    }

    /// @notice An unregistered source state machine is rejected fail-closed (reverse map returns chainId 0).
    function test_OnAcceptUnknownSourceReverts() public {
        PostRequest memory request = _inboundRequest(hex"01", 1, 1);
        request.source = bytes("EVM-999999");
        vm.expectRevert(
            abi.encodeWithSelector(IHyperbridgeGatewayAdapter.HyperbridgeUnknownSource.selector, bytes("EVM-999999"))
        );
        host.deliverPostRequest(diamond, request, relayer);
    }

    function test_OnAcceptUntrustedModuleReverts() public {
        PostRequest memory request = _inboundRequest(hex"01", 1, 1);
        request.from = abi.encodePacked(address(0xDEAD));
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperbridgeGatewayAdapter.HyperbridgeUntrustedModule.selector, abi.encodePacked(address(0xDEAD))
            )
        );
        host.deliverPostRequest(diamond, request, relayer);
    }

    /// @notice Hardening: a source registered BEFORE its remote module cannot satisfy auth via an empty
    ///         `from` against the empty registered remote — empty never matches.
    function test_OnAcceptEmptyRegisteredRemoteVsEmptyFromReverts() public {
        vm.prank(admin);
        adapter.registerStateMachine(555); // remote module intentionally left unset
        PostRequest memory request = _inboundRequest(hex"01", 1, 1);
        request.source = bytes("EVM-555");
        request.from = "";
        vm.expectRevert(
            abi.encodeWithSelector(IHyperbridgeGatewayAdapter.HyperbridgeUntrustedModule.selector, bytes(""))
        );
        host.deliverPostRequest(diamond, request, relayer);
    }

    /// @notice Suite-level dedup on the host-side-unique (source, PROTOCOL nonce): a second delivery of the
    ///         same pair reverts; a different protocol nonce passes.
    function test_OnAcceptReplayReverts() public {
        host.deliverPostRequest(diamond, _inboundRequest(hex"01", 7, 42), relayer);

        bytes32 dedupKey = keccak256(abi.encode(REMOTE_SM_ID, uint64(42)));
        vm.expectRevert(
            abi.encodeWithSelector(
                IHyperbridgeGatewayAdapter.HyperbridgeMessageAlreadyExecuted.selector, REMOTE_CHAIN, dedupKey
            )
        );
        host.deliverPostRequest(diamond, _inboundRequest(hex"01", 7, 42), relayer);

        // A different protocol nonce is a different request — it passes.
        host.deliverPostRequest(diamond, _inboundRequest(hex"01", 8, 43), relayer);
        assertEq(recipient.calls(), 2, "different (source, nonce) delivered");
    }

    /// @notice Hardening: a message whose recipient targets a different chain than this one is rejected
    ///         (defense-in-depth against a rogue/misconfigured trusted remote misdirecting delivery).
    function test_OnAcceptWrongDestinationChainReverts() public {
        PostRequest memory request = _inboundRequest(hex"01", 1, 1);
        bytes memory senderInterop = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, remoteSender);
        bytes memory wrongChainRecip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(recipient));
        request.body = abi.encode(senderInterop, wrongChainRecip, hex"01", uint256(1));
        vm.expectRevert(
            abi.encodeWithSelector(IHyperbridgeGatewayAdapter.HyperbridgeWrongDestinationChain.selector, REMOTE_CHAIN)
        );
        host.deliverPostRequest(diamond, request, relayer);
    }

    /// @notice A RAW-registered substrate-style state machine id round-trips through `onAccept` auth: the
    ///         source `bytes("POLKADOT-3367")` resolves to its local routing handle and its trusted module
    ///         authenticates deliveries.
    function test_OnAcceptRawSubstrateSourceRoundTrips() public {
        bytes memory polkadotModule = hex"0123456789abcdef0123456789abcdef01234567deadbeef"; // non-EVM module id
        vm.startPrank(admin);
        adapter.registerStateMachineRaw(POLKADOT_HANDLE, POLKADOT_SM_ID);
        adapter.registerRemoteModule(POLKADOT_HANDLE, polkadotModule);
        vm.stopPrank();

        bytes memory senderInterop = InteroperableAddress.formatEvmV1(POLKADOT_HANDLE, remoteSender);
        bytes memory localRecip = InteroperableAddress.formatEvmV1(block.chainid, address(recipient));
        PostRequest memory request = PostRequest({
            source: POLKADOT_SM_ID,
            dest: bytes("EVM-31337"),
            nonce: 9,
            from: polkadotModule,
            to: abi.encodePacked(diamond),
            timeoutTimestamp: 0,
            body: abi.encode(senderInterop, localRecip, hex"5eed", uint256(4))
        });
        host.deliverPostRequest(diamond, request, relayer);

        assertEq(recipient.calls(), 1);
        assertEq(recipient.lastReceiveId(), _sendId(POLKADOT_HANDLE, 4), "handle chainId keys the receiveId");
        assertEq(recipient.lastPayload(), hex"5eed");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  TIMEOUT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The host's timeout notification decodes OUR envelope and emits the original sendId + sender +
    ///         payload. EMIT-ONLY v1: the fee refund itself is HOST-SIDE to `DispatchPost.payer` (= the user).
    function test_OnPostRequestTimeoutEmitsDecodedEnvelope() public {
        // A request we actually dispatched (timeout fires on the SOURCE chain, so source chainid = ours).
        vm.prank(user);
        adapter.sendMessageWithFee(recip, hex"deadbeef", RELAYER_FEE);

        PostRequest memory timedOut = PostRequest({
            source: bytes("EVM-31337"),
            dest: REMOTE_SM_ID,
            nonce: 1,
            from: abi.encodePacked(diamond),
            to: remoteModule,
            timeoutTimestamp: uint64(block.timestamp + DEST_TIMEOUT),
            body: host.lastBody()
        });

        vm.expectEmit(true, false, false, true);
        emit IHyperbridgeGatewayAdapter.HyperbridgeRequestTimedOut(
            _sendId(block.chainid, 1), InteroperableAddress.formatEvmV1(block.chainid, user), hex"deadbeef"
        );
        host.timeoutPostRequest(diamond, timedOut);
    }

    function test_OnPostRequestTimeoutNotHostReverts() public {
        PostRequest memory request = _inboundRequest(hex"01", 1, 1);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IHyperbridgeGatewayAdapter.HyperbridgeNotHost.selector, user));
        adapter.onPostRequestTimeout(request);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               UNUSED HOOKS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice All four unused IIsmpModule hooks revert {HyperbridgeUnsupportedHook} — the adapter dispatches
    ///         neither GETs nor responses, so silently accepting them would be a spoofable no-op surface.
    function test_UnusedHooksRevert() public {
        PostRequest memory request = _inboundRequest(hex"01", 1, 1);
        PostResponse memory postResponse = PostResponse({request: request, response: hex"01", timeoutTimestamp: 0});
        GetRequest memory getRequest;

        vm.startPrank(address(host));
        vm.expectRevert(IHyperbridgeGatewayAdapter.HyperbridgeUnsupportedHook.selector);
        adapter.onPostResponse(IncomingPostResponse({response: postResponse, relayer: relayer}));

        IncomingGetResponse memory getResponse;
        vm.expectRevert(IHyperbridgeGatewayAdapter.HyperbridgeUnsupportedHook.selector);
        adapter.onGetResponse(getResponse);

        vm.expectRevert(IHyperbridgeGatewayAdapter.HyperbridgeUnsupportedHook.selector);
        adapter.onPostResponseTimeout(postResponse);

        vm.expectRevert(IHyperbridgeGatewayAdapter.HyperbridgeUnsupportedHook.selector);
        adapter.onGetTimeout(getRequest);
        vm.stopPrank();
    }
}
