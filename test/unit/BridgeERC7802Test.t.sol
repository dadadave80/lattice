// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {BridgeERC7802} from "@lattice/crosschain/BridgeERC7802.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {BridgeERC7802Lib} from "@lattice/crosschain/libraries/BridgeERC7802Lib.sol";
import {FUNGIBLE_BRIDGE_TAG} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {CrosschainLinkLib} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";
import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";
import {IERC7802} from "@lattice/interfaces/external/IERC7802.sol";
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

/// @notice Minimal ERC-7802 token: crosschainMint/Burn adjust balances.
contract MockERC7802 is IERC7802 {
    mapping(address => uint256) public balanceOf;
    uint256 public totalSupply;

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
        totalSupply += amt;
    }

    function crosschainMint(address to, uint256 amt) external {
        balanceOf[to] += amt;
        totalSupply += amt;
        emit CrosschainMint(to, amt, msg.sender);
    }

    function crosschainBurn(address from, uint256 amt) external {
        balanceOf[from] -= amt;
        totalSupply -= amt;
        emit CrosschainBurn(from, amt, msg.sender);
    }
}

/// @notice Combines AccessControl + CrosschainLink + BridgeERC7802 for testing (co-mounted facets).
contract MockBridgeERC7802Contract is AccessControl, CrosschainLink, BridgeERC7802 {
    function initialize(address admin_, address token_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        CrosschainLinkLib.__CrosschainLink_init();
        BridgeERC7802Lib.__BridgeERC7802_init(token_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

contract BridgeERC7802Test is Test {
    MockBridgeERC7802Contract bridge;
    MockERC7802 token;
    MockGateway gateway;

    address admin = address(0x1);
    address user = address(0x2);
    address remoteBridge = address(0xB0B);
    address recipient = address(0xCAFE);

    uint256 constant REMOTE_CHAIN = 10;
    uint256 constant AMT = 100e18;
    bytes32 constant RECEIVE_ID = keccak256("msg-1");

    bytes counterpart;
    bytes toRecipient;

    function setUp() public {
        token = new MockERC7802();
        bridge = new MockBridgeERC7802Contract();
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

    function _inboundPayload(address to, uint256 amount) internal view returns (bytes memory) {
        return abi.encode(counterpart, abi.encodePacked(to), amount);
    }

    function test_CrosschainTransferBurnsAndSends() public {
        vm.startPrank(user);
        vm.expectEmit(true, true, false, true);
        emit IBridgeFungible.CrosschainFungibleTransferSent(gateway.SEND_ID(), user, toRecipient, AMT);
        bytes32 sendId = bridge.crosschainTransfer(toRecipient, AMT);
        vm.stopPrank();

        assertEq(sendId, gateway.SEND_ID());
        assertEq(token.balanceOf(user), 1000e18 - AMT, "burned from sender");
        assertEq(token.balanceOf(address(bridge)), 0, "no custody for mint/burn bridge");
        assertEq(gateway.lastRecipient(), counterpart);
        assertEq(bytes4(gateway.lastPayload()), FUNGIBLE_BRIDGE_TAG);
    }

    function test_ReceiveMints() public {
        vm.prank(address(gateway));
        vm.expectEmit(true, false, true, true);
        emit IBridgeFungible.CrosschainFungibleTransferReceived(RECEIVE_ID, counterpart, recipient, AMT);
        bridge.receiveMessage(
            RECEIVE_ID, counterpart, bytes.concat(FUNGIBLE_BRIDGE_TAG, _inboundPayload(recipient, AMT))
        );

        assertEq(token.balanceOf(recipient), AMT, "minted to recipient");
    }

    function test_ProcessMessageRevertsOnDirectCall() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IBridgeFungible.BridgeUnauthorizedCaller.selector, user));
        bridge.processMessage(RECEIVE_ID, counterpart, _inboundPayload(recipient, AMT));
    }

    function test_InitRevertsZeroToken() public {
        MockBridgeERC7802Contract b = new MockBridgeERC7802Contract();
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
