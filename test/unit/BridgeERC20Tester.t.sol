// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {BridgeERC20} from "@lattice/crosschain/BridgeERC20.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {BridgeERC20Lib} from "@lattice/crosschain/libraries/BridgeERC20Lib.sol";
import {FUNGIBLE_BRIDGE_TAG} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {CrosschainLinkLib} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";
import {IBridgeFungible} from "@lattice/interfaces/IBridgeFungible.sol";
import {ICrosschainLink} from "@lattice/interfaces/ICrosschainLink.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

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

/// @notice Minimal ERC-20 (1:1 transfers).
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }

    function approve(address s, uint256 v) external returns (bool) {
        allowance[msg.sender][s] = v;
        return true;
    }

    function transfer(address to, uint256 v) external returns (bool) {
        balanceOf[msg.sender] -= v;
        balanceOf[to] += v;
        return true;
    }

    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        allowance[f][msg.sender] -= v;
        balanceOf[f] -= v;
        balanceOf[t] += v;
        return true;
    }
}

/// @notice Fee-on-transfer ERC-20: `transferFrom` credits one wei less than requested.
contract MockFeeERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }

    function approve(address s, uint256 v) external returns (bool) {
        allowance[msg.sender][s] = v;
        return true;
    }

    function transfer(address to, uint256 v) external returns (bool) {
        balanceOf[msg.sender] -= v;
        balanceOf[to] += v;
        return true;
    }

    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        allowance[f][msg.sender] -= v;
        balanceOf[f] -= v;
        balanceOf[t] += v - 1; // burn a 1-wei fee
        return true;
    }
}

/// @notice Combines AccessControl + CrosschainLink + BridgeERC20 for testing (co-mounted facets).
contract MockBridgeERC20Contract is AccessControl, CrosschainLink, BridgeERC20 {
    function initialize(address admin_, address token_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        CrosschainLinkLib.__CrosschainLink_init();
        BridgeERC20Lib.__BridgeERC20_init(token_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

contract BridgeERC20Tester is Test {
    MockBridgeERC20Contract bridge;
    MockERC20 token;
    MockGateway gateway;

    address admin = address(0x1);
    address user = address(0x2);
    address remoteBridge = address(0xB0B);
    address recipient = address(0xCAFE);

    uint256 constant REMOTE_CHAIN = 10;
    uint256 constant AMT = 100e18;
    bytes32 constant RECEIVE_ID = keccak256("msg-1");

    bytes counterpart; // remote bridge interop addr (the authorized source sender)
    bytes toRecipient; // full interop addr to deliver to on the remote chain

    function setUp() public {
        token = new MockERC20();
        bridge = new MockBridgeERC20Contract();
        bridge.initialize(admin, address(token));
        gateway = new MockGateway();

        counterpart = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, remoteBridge);
        toRecipient = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, recipient);

        vm.startPrank(admin);
        bridge.setLink(address(gateway), counterpart, false);
        bridge.setHandler(FUNGIBLE_BRIDGE_TAG, address(bridge));
        vm.stopPrank();

        token.mint(user, 1000e18);
    }

    /// @dev Builds a tag-stripped inbound payload crediting `to` with `amount`.
    function _inboundPayload(address to, uint256 amount) internal view returns (bytes memory) {
        return abi.encode(counterpart, abi.encodePacked(to), amount);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             OUTBOUND (LOCK)
    //////////////////////////////////////////////////////////////////////////*//

    function test_CrosschainTransferLocksAndSends() public {
        vm.startPrank(user);
        token.approve(address(bridge), AMT);
        vm.expectEmit(true, true, false, true);
        emit IBridgeFungible.CrosschainFungibleTransferSent(gateway.SEND_ID(), user, toRecipient, AMT);
        bytes32 sendId = bridge.crosschainTransfer(toRecipient, AMT);
        vm.stopPrank();

        assertEq(sendId, gateway.SEND_ID());
        assertEq(token.balanceOf(address(bridge)), AMT, "custody locked");
        assertEq(token.balanceOf(user), 1000e18 - AMT);
        assertEq(gateway.lastRecipient(), counterpart, "routed to counterpart");
        // payload carries the fungible-bridge tag
        bytes memory p = gateway.lastPayload();
        assertEq(bytes4(p), FUNGIBLE_BRIDGE_TAG, "payload tag");
    }

    function test_CrosschainTransferRejectsFeeOnTransfer() public {
        MockFeeERC20 feeToken = new MockFeeERC20();
        MockBridgeERC20Contract feeBridge = new MockBridgeERC20Contract();
        feeBridge.initialize(admin, address(feeToken));
        vm.startPrank(admin);
        feeBridge.setLink(address(gateway), counterpart, false);
        feeBridge.setHandler(FUNGIBLE_BRIDGE_TAG, address(feeBridge));
        vm.stopPrank();
        feeToken.mint(user, 1000e18);

        vm.startPrank(user);
        feeToken.approve(address(feeBridge), AMT);
        vm.expectRevert(abi.encodeWithSelector(IBridgeFungible.BridgeAmountMismatch.selector, AMT, AMT - 1));
        feeBridge.crosschainTransfer(toRecipient, AMT);
        vm.stopPrank();
    }

    function test_CrosschainTransferRejectsBadRecipientLength() public {
        // A `to` whose address part is not 20 bytes must be rejected on SEND, before any funds are locked.
        // The inbound decode requires exactly 20 bytes, so otherwise the locked funds would be stranded.
        bytes memory badTo = InteroperableAddress.formatV1(bytes2(0x0000), hex"0a", new bytes(32));
        vm.startPrank(user);
        token.approve(address(bridge), AMT);
        vm.expectRevert(IBridgeFungible.BridgeInvalidRecipient.selector);
        bridge.crosschainTransfer(badTo, AMT);
        vm.stopPrank();
        assertEq(token.balanceOf(address(bridge)), 0, "no funds locked on a rejected send");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INBOUND (RELEASE)
    //////////////////////////////////////////////////////////////////////////*//

    function test_ReceiveReleasesCustody() public {
        token.mint(address(bridge), 500e18); // pre-fund custody

        vm.prank(address(gateway));
        vm.expectEmit(true, false, true, true);
        emit IBridgeFungible.CrosschainFungibleTransferReceived(RECEIVE_ID, counterpart, recipient, AMT);
        bridge.receiveMessage(
            RECEIVE_ID, counterpart, bytes.concat(FUNGIBLE_BRIDGE_TAG, _inboundPayload(recipient, AMT))
        );

        assertEq(token.balanceOf(recipient), AMT, "released to recipient");
        assertEq(token.balanceOf(address(bridge)), 500e18 - AMT);
    }

    function test_ReceiveRejectsNon20ByteRecipient() public {
        bytes memory badAddr = abi.encodePacked(recipient, uint8(0x11)); // 21 bytes
        bytes memory payload = bytes.concat(FUNGIBLE_BRIDGE_TAG, abi.encode(counterpart, badAddr, AMT));
        vm.prank(address(gateway));
        vm.expectRevert(IBridgeFungible.BridgeInvalidRecipient.selector);
        bridge.receiveMessage(RECEIVE_ID, counterpart, payload);
    }

    function test_ReceiveReplayReverts() public {
        token.mint(address(bridge), 500e18);
        bytes memory msg_ = bytes.concat(FUNGIBLE_BRIDGE_TAG, _inboundPayload(recipient, AMT));
        vm.startPrank(address(gateway));
        bridge.receiveMessage(RECEIVE_ID, counterpart, msg_);
        vm.expectRevert(abi.encodeWithSelector(ICrosschainLink.CrosschainMessageAlreadyProcessed.selector, RECEIVE_ID));
        bridge.receiveMessage(RECEIVE_ID, counterpart, msg_);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       DIRECT-CALL AUTH GUARD
    //////////////////////////////////////////////////////////////////////////*//

    function test_ProcessMessageRevertsOnDirectCall() public {
        // A user calling processMessage directly (not via receiveMessage) must be rejected, else they
        // could forge an inbound mint/release.
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IBridgeFungible.BridgeUnauthorizedCaller.selector, user));
        bridge.processMessage(RECEIVE_ID, counterpart, _inboundPayload(recipient, AMT));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitRevertsZeroToken() public {
        MockBridgeERC20Contract b = new MockBridgeERC20Contract();
        vm.expectRevert(IBridgeFungible.BridgeZeroToken.selector);
        b.initialize(admin, address(0));
    }

    function test_TokenGetter() public view {
        assertEq(bridge.token(), address(token));
    }

    function test_SupportsInterfaceBridgeFungible() public view {
        assertTrue(bridge.supportsInterface(type(IBridgeFungible).interfaceId));
    }
}
