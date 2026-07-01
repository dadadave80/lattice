// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CCIPGatewayAdapter} from "@lattice/crosschain/CCIPGatewayAdapter.sol";
import {CCIPGatewayAdapterLib} from "@lattice/crosschain/libraries/CCIPGatewayAdapterLib.sol";
import {ICCIPGatewayAdapter} from "@lattice/interfaces/crosschain/ICCIPGatewayAdapter.sol";
import {Client} from "@lattice/interfaces/external/CCIPClient.sol";
import {IAny2EVMMessageReceiver} from "@lattice/interfaces/external/IAny2EVMMessageReceiver.sol";
import {IAny2EVMMessageReceiverV2} from "@lattice/interfaces/external/IAny2EVMMessageReceiverV2.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";
import {IRouterClient} from "@lattice/interfaces/external/IRouterClient.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal CCIP router mock. Records the last `ccipSend`, pulls fees the way the real router does
///         (native via `msg.value`, ERC-20 via `transferFrom`), and returns a deterministic message id.
contract MockCCIPRouter is IRouterClient {
    uint256 public feeAmount = 0.01 ether;
    uint64 public lastSelector;
    bytes public lastReceiver;
    bytes public lastData;
    address public lastFeeToken;
    bytes public lastExtraArgs;
    uint256 public sends;

    function setFee(uint256 f) external {
        feeAmount = f;
    }

    function isChainSupported(uint64) external pure returns (bool) {
        return true;
    }

    function getFee(uint64, Client.EVM2AnyMessage memory) external view returns (uint256) {
        return feeAmount;
    }

    function ccipSend(uint64 selector, Client.EVM2AnyMessage calldata message) external payable returns (bytes32) {
        lastSelector = selector;
        lastReceiver = message.receiver;
        lastData = message.data;
        lastFeeToken = message.feeToken;
        lastExtraArgs = message.extraArgs;
        if (message.feeToken == address(0)) {
            require(msg.value >= feeAmount, "fee");
        } else {
            IERC20(message.feeToken).transferFrom(msg.sender, address(this), feeAmount);
        }
        return keccak256(abi.encode("ccip-msg", ++sends));
    }
}

/// @notice Minimal ERC-20 for the LINK fee path (mint/approve/transferFrom).
contract MockERC20 is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function name() external pure returns (string memory) {
        return "Mock LINK";
    }

    function symbol() external pure returns (string memory) {
        return "mLINK";
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

contract MockCCIPAdapter is AccessControl, CCIPGatewayAdapter {
    function initialize(address admin_, address router_, address feeToken_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        CCIPGatewayAdapterLib.__CCIPGatewayAdapter_init(router_, feeToken_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract CCIPGatewayAdapterTest is Test {
    MockCCIPAdapter adapter;
    MockCCIPRouter ccipRouter;
    MockRecipient recipient;
    MockERC20 link;

    address admin = address(0x1);
    address user = address(0x2);
    address remoteGw = address(0xA11CE);
    address finalRecipient = address(0xCAFE);

    uint256 constant REMOTE_CHAIN = 10;
    uint64 constant REMOTE_SELECTOR = 5_009_297_550_715_157_269; // arbitrary CCIP-style selector
    uint256 constant DEST_GAS = 200_000;

    bytes recip; // dest recipient (ERC-7930)
    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        ccipRouter = new MockCCIPRouter();
        adapter = new MockCCIPAdapter();
        adapter.initialize(admin, address(ccipRouter), address(0)); // native fee by default
        recipient = new MockRecipient();
        link = new MockERC20();

        recip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, finalRecipient);

        vm.startPrank(admin);
        adapter.registerChainSelector(REMOTE_CHAIN, REMOTE_SELECTOR);
        adapter.registerRemoteGateway(REMOTE_CHAIN, remoteGw);
        adapter.configureDestination(REMOTE_CHAIN, DEST_GAS, true);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterChainSelector() public view {
        assertEq(adapter.getChainSelector(REMOTE_CHAIN), REMOTE_SELECTOR);
        assertEq(adapter.getChainId(REMOTE_SELECTOR), REMOTE_CHAIN);
    }

    function test_RegisterChainSelectorRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerChainSelector(99, 99);
    }

    function test_RegisterChainSelectorDuplicateReverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPGatewayAdapter.ChainSelectorAlreadyRegistered.selector, REMOTE_CHAIN)
        );
        adapter.registerChainSelector(REMOTE_CHAIN, 1234);
    }

    function test_RegisterRemoteGateway() public view {
        assertEq(adapter.getRemoteGateway(REMOTE_CHAIN), remoteGw);
    }

    function test_RegisterRemoteGatewayDuplicateReverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPGatewayAdapter.RemoteGatewayAlreadyRegistered.selector, REMOTE_CHAIN)
        );
        adapter.registerRemoteGateway(REMOTE_CHAIN, address(0xBEEF));
    }

    function test_ConfigureDestination() public view {
        assertEq(adapter.getDestinationGasLimit(REMOTE_CHAIN), DEST_GAS);
        assertTrue(adapter.getAllowOutOfOrderExecution(REMOTE_CHAIN));
    }

    function test_ConfigureDestinationRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.configureDestination(REMOTE_CHAIN, 1, false);
    }

    function test_SetFeeToken() public {
        vm.prank(admin);
        adapter.setFeeToken(address(link));
        assertEq(adapter.feeToken(), address(link));
    }

    function test_SetFeeTokenRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.setFeeToken(address(link));
    }

    function test_RouterAndFeeToken() public view {
        assertEq(adapter.router(), address(ccipRouter));
        assertEq(adapter.feeToken(), address(0));
    }

    function test_SupportsAttributeAlwaysFalse() public view {
        assertFalse(adapter.supportsAttribute(bytes4(0x12345678)));
        assertFalse(adapter.supportsAttribute(bytes4(0)));
    }

    function test_SupportsInterfaceGatewaySource() public view {
        assertTrue(adapter.supportsInterface(type(IERC7786GatewaySource).interfaceId));
    }

    function test_SupportsInterfaceCCIPReceiver() public view {
        // The router calls supportsInterface(0x85572ffb) BEFORE delivery; must be true.
        assertTrue(adapter.supportsInterface(type(IAny2EVMMessageReceiver).interfaceId));
        assertEq(type(IAny2EVMMessageReceiver).interfaceId, bytes4(0x85572ffb));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    function _wirePayload(address sender, bytes memory inner) internal view returns (bytes memory) {
        return abi.encode(InteroperableAddress.formatEvmV1(block.chainid, sender), recip, inner);
    }

    function test_SendNativeFeeSubmitsToRouter() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        bytes32 id = adapter.sendMessage{value: 0.01 ether}(recip, hex"deadbeef", new bytes[](0));

        assertEq(id, bytes32(0), "fully-dispatched send returns 0 per ERC-7786");
        assertEq(ccipRouter.lastSelector(), REMOTE_SELECTOR);
        assertEq(ccipRouter.lastReceiver(), abi.encode(remoteGw), "receiver = remote adapter");
        assertEq(ccipRouter.lastFeeToken(), address(0), "native fee");
        assertEq(ccipRouter.lastData(), _wirePayload(user, hex"deadbeef"), "wire payload");
        // extraArgs = GENERIC_EXTRA_ARGS_V2_TAG || abi.encode(GenericExtraArgsV2{DEST_GAS, true})
        assertEq(
            ccipRouter.lastExtraArgs(),
            Client._argsToBytes(Client.GenericExtraArgsV2({gasLimit: DEST_GAS, allowOutOfOrderExecution: true}))
        );
    }

    function test_SendNativeFeeRefundsExcess() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        adapter.sendMessage{value: 0.05 ether}(recip, hex"01", new bytes[](0));
        // forwarded 0.01 to router, refunded 0.04 to user
        assertEq(user.balance, 1 ether - 0.01 ether, "excess refunded");
        assertEq(address(ccipRouter).balance, 0.01 ether, "router got fee");
    }

    function test_SendEmitsMessageSent() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectEmit(false, false, false, false);
        emit IERC7786GatewaySource.MessageSent(bytes32(0), "", "", "", 0, new bytes[](0));
        adapter.sendMessage{value: 0.01 ether}(recip, hex"deadbeef", new bytes[](0));
    }

    function test_SendLinkFeePulledFromSender() public {
        vm.prank(admin);
        adapter.setFeeToken(address(link));
        link.mint(user, 1 ether);
        vm.prank(user);
        link.approve(address(adapter), type(uint256).max);

        vm.prank(user);
        bytes32 id = adapter.sendMessage(recip, hex"c0ffee", new bytes[](0));

        assertEq(id, bytes32(0));
        assertEq(ccipRouter.lastFeeToken(), address(link));
        assertEq(link.balanceOf(user), 1 ether - 0.01 ether, "fee pulled from sender, not the Diamond");
        assertEq(link.balanceOf(address(adapter)), 0, "Diamond holds no residual (drain-safe)");
        assertEq(link.balanceOf(address(ccipRouter)), 0.01 ether, "router got fee");
    }

    function test_SendLinkFeeNoApprovalReverts() public {
        vm.prank(admin);
        adapter.setFeeToken(address(link));
        link.mint(user, 1 ether); // minted but not approved to the adapter
        vm.prank(user);
        vm.expectRevert(); // BridgeFungibleLib pull fails without allowance
        adapter.sendMessage(recip, hex"01", new bytes[](0));
    }

    function test_SendInsufficientNativeFeeReverts() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ICCIPGatewayAdapter.InsufficientFee.selector, 0.001 ether, 0.01 ether));
        adapter.sendMessage{value: 0.001 ether}(recip, hex"01", new bytes[](0));
    }

    function test_SendUnknownDestinationReverts() public {
        bytes memory unknown = InteroperableAddress.formatEvmV1(999, finalRecipient);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ICCIPGatewayAdapter.UnknownDestinationChain.selector, 999));
        adapter.sendMessage(unknown, hex"01", new bytes[](0));
    }

    function test_SendUnconfiguredDestinationReverts() public {
        // selector + remote registered but no gas configured
        vm.startPrank(admin);
        adapter.registerChainSelector(77, 7777);
        adapter.registerRemoteGateway(77, address(0xD00D));
        vm.stopPrank();
        bytes memory dest = InteroperableAddress.formatEvmV1(77, finalRecipient);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ICCIPGatewayAdapter.DestinationNotConfigured.selector, 77));
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

    function _inbound(bytes32 messageId, bytes memory inner) internal view returns (Client.Any2EVMMessage memory) {
        bytes memory senderInterop = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0x5151));
        bytes memory localRecip = InteroperableAddress.formatEvmV1(block.chainid, address(recipient));
        return Client.Any2EVMMessage({
            messageId: messageId,
            sourceChainSelector: REMOTE_SELECTOR,
            sender: abi.encode(remoteGw),
            data: abi.encode(senderInterop, localRecip, inner),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
    }

    function test_ReceiveDeliversToRecipient() public {
        bytes32 mid = keccak256("mid-1");
        vm.prank(address(ccipRouter));
        adapter.ccipReceive(_inbound(mid, hex"c0ffee"));

        assertEq(recipient.calls(), 1);
        assertEq(recipient.lastReceiveId(), mid, "receiveId = ccip messageId");
        assertEq(recipient.lastPayload(), hex"c0ffee");
        assertEq(recipient.lastSender(), InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0x5151)));
    }

    function test_ReceiveReplayReverts() public {
        bytes32 mid = keccak256("mid-1");
        vm.startPrank(address(ccipRouter));
        adapter.ccipReceive(_inbound(mid, hex"01"));
        vm.expectRevert(abi.encodeWithSelector(ICCIPGatewayAdapter.MessageAlreadyExecuted.selector, REMOTE_CHAIN, mid));
        adapter.ccipReceive(_inbound(mid, hex"01"));
        vm.stopPrank();
    }

    function test_ReceiveWrongRouterReverts() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ICCIPGatewayAdapter.NotRouter.selector, user));
        adapter.ccipReceive(_inbound(keccak256("x"), hex"01"));
    }

    function test_ReceiveWrongOriginReverts() public {
        Client.Any2EVMMessage memory m = _inbound(keccak256("x"), hex"01");
        m.sender = abi.encode(address(0xDEAD)); // not the registered remote gateway
        vm.prank(address(ccipRouter));
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPGatewayAdapter.InvalidOriginGateway.selector, REMOTE_SELECTOR, m.sender)
        );
        adapter.ccipReceive(m);
    }

    function test_ReceiveUnknownSelectorReverts() public {
        Client.Any2EVMMessage memory m = _inbound(keccak256("x"), hex"01");
        m.sourceChainSelector = 424242; // unmapped → chainId 0 → no remote gateway
        vm.prank(address(ccipRouter));
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPGatewayAdapter.InvalidOriginGateway.selector, uint64(424242), m.sender)
        );
        adapter.ccipReceive(m);
    }

    function test_ReceiveMalformedSenderReverts() public {
        // A non-32-byte sender (e.g. a non-EVM/garbled source) must surface the typed error, not a bare
        // abi.decode revert, for a registered source selector.
        Client.Any2EVMMessage memory m = _inbound(keccak256("x"), hex"01");
        m.sender = hex"1234";
        vm.prank(address(ccipRouter));
        vm.expectRevert(
            abi.encodeWithSelector(ICCIPGatewayAdapter.InvalidOriginGateway.selector, REMOTE_SELECTOR, m.sender)
        );
        adapter.ccipReceive(m);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 V2 / CCV
    //////////////////////////////////////////////////////////////////////////*//

    function _ccvs() internal pure returns (address[] memory req, address[] memory opt) {
        req = new address[](1);
        req[0] = address(0xCC1);
        opt = new address[](2);
        opt[0] = address(0xCC2);
        opt[1] = address(0xCC3);
    }

    function test_SupportsInterfaceCCIPReceiverV2() public view {
        // CCV-enabled lanes detect the receiver via the V2 interfaceId. Solidity's type().interfaceId
        // excludes inherited functions, so V2's id is the getCCVsAndFinalityConfig selector — exactly the
        // value the CCIP router queries.
        assertTrue(adapter.supportsInterface(type(IAny2EVMMessageReceiverV2).interfaceId));
        assertEq(type(IAny2EVMMessageReceiverV2).interfaceId, bytes4(0x1bfc84d0));
    }

    function test_GetCCVsAndFinalityConfigDefault() public view {
        (address[] memory req, address[] memory opt, uint8 thr, bytes4 fin) =
            adapter.getCCVsAndFinalityConfig(REMOTE_SELECTOR, "");
        assertEq(req.length, 0);
        assertEq(opt.length, 0);
        assertEq(thr, 0);
        assertEq(fin, bytes4(0), "unconfigured => require full finality");
    }

    function test_ConfigureCCVAndRead() public {
        (address[] memory req, address[] memory opt) = _ccvs();
        bytes4 fin = bytes4(uint32(0x00010000)); // a non-zero finality flag

        vm.prank(admin);
        adapter.configureCCV(REMOTE_CHAIN, req, opt, 1, fin);

        // read by chainId (admin getter)
        (address[] memory rReq, address[] memory rOpt, uint8 rThr, bytes4 rFin) = adapter.getCCVConfig(REMOTE_CHAIN);
        assertEq(rReq.length, 1);
        assertEq(rReq[0], address(0xCC1));
        assertEq(rOpt.length, 2);
        assertEq(rOpt[1], address(0xCC3));
        assertEq(rThr, 1);
        assertEq(rFin, fin);

        // read by selector (what the CCIP router calls)
        (address[] memory sReq,,, bytes4 sFin) = adapter.getCCVsAndFinalityConfig(REMOTE_SELECTOR, "");
        assertEq(sReq[0], address(0xCC1));
        assertEq(sFin, fin);
    }

    function test_ConfigureCCVRevertsNonAdmin() public {
        (address[] memory req, address[] memory opt) = _ccvs();
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.configureCCV(REMOTE_CHAIN, req, opt, 1, bytes4(0));
    }

    function test_ConfigureCCVInvalidThresholdReverts() public {
        address[] memory req = new address[](0);
        address[] memory opt = new address[](1);
        opt[0] = address(0xCC2);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ICCIPGatewayAdapter.InvalidCCVThreshold.selector, uint8(2), uint256(1)));
        adapter.configureCCV(REMOTE_CHAIN, req, opt, 2, bytes4(0)); // threshold 2 > 1 optional
    }
}
