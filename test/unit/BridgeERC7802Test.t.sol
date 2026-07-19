// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BridgeERC7802TestBase} from "@lattice-test/base/BridgeERC7802TestBase.sol";
import {BridgeERC7802} from "@lattice/crosschain/BridgeERC7802.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {FUNGIBLE_BRIDGE_TAG} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {IERC7802} from "@lattice/interfaces/external/ercs/IERC7802.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

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

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

contract BridgeERC7802Test is BridgeERC7802TestBase {
    address internal diamond; // the assembled ERC-7802 mint/burn bridge diamond
    BridgeERC7802 bridge; // typed handle on the diamond (bridge calls dispatch through it)
    CrosschainLink link; // typed handle for the co-mounted messaging registry
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
        diamond = _deployBridgeERC7802(admin, address(token));
        bridge = BridgeERC7802(diamond);
        link = CrosschainLink(diamond);
        gateway = new MockGateway();

        counterpart = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, remoteBridge);
        toRecipient = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, recipient);

        vm.startPrank(admin);
        link.setLink(address(gateway), counterpart, false);
        link.setHandler(FUNGIBLE_BRIDGE_TAG, address(diamond));
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
        link.receiveMessage(RECEIVE_ID, counterpart, bytes.concat(FUNGIBLE_BRIDGE_TAG, _inboundPayload(recipient, AMT)));

        assertEq(token.balanceOf(recipient), AMT, "minted to recipient");
    }

    function test_ProcessMessageRevertsOnDirectCall() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IBridgeFungible.BridgeUnauthorizedCaller.selector, user));
        bridge.processMessage(RECEIVE_ID, counterpart, _inboundPayload(recipient, AMT));
    }

    function test_InitRevertsZeroToken() public {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, address(0));
        Diamond d = new Diamond();
        vm.expectRevert(IBridgeFungible.BridgeZeroToken.selector);
        d.initialize(cuts, init, initCalldata);
    }

    function test_TokenGetter() public view {
        assertEq(bridge.token(), address(token));
    }

    function test_SupportsInterfaceBridgeFungible() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IBridgeFungible).interfaceId));
    }
}
