// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ERC20CrosschainTestBase} from "@lattice-test/base/ERC20CrosschainTestBase.sol";
import {FUNGIBLE_BRIDGE_TAG} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {ICrosschainLink} from "@lattice/interfaces/crosschain/ICrosschainLink.sol";
import {IERC7786MessageHandler} from "@lattice/interfaces/crosschain/IERC7786MessageHandler.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {IERC7786Recipient} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @notice External gateway mock — NOT the facet under test; kept as-is (implements IERC7786GatewaySource).
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

/// @notice Self-bridging ERC-20 (ERC20 + CrosschainLink + ERC20Crosschain) exercised through a REAL diamond,
///         assembled by the ready-to-deploy {DeployERC20Crosschain} recipe — not a flattened inheritance mock.
contract ERC20CrosschainTest is ERC20CrosschainTestBase {
    MockGateway gateway;

    address admin = address(0x1);
    address holder = address(0x2);
    address remotePeer = address(0xB0B);
    address recipient = address(0xCAFE);

    uint256 constant REMOTE_CHAIN = 10;
    uint256 constant INITIAL = 1000e18;
    uint256 constant AMT = 100e18;
    bytes32 constant RECEIVE_ID = keccak256("msg-1");

    bytes counterpart;
    bytes toRecipient;

    function setUp() public {
        diamond = _deployERC20Crosschain(admin, "Lattice Omni", "lOMNI");
        helper.mint(holder, INITIAL);
        gateway = new MockGateway();

        counterpart = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, remotePeer);
        toRecipient = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, recipient);

        vm.startPrank(admin);
        ICrosschainLink(diamond).setLink(address(gateway), counterpart, false);
        ICrosschainLink(diamond).setHandler(FUNGIBLE_BRIDGE_TAG, diamond);
        vm.stopPrank();
    }

    function _inbound(address to, uint256 amount) internal view returns (bytes memory) {
        return abi.encode(counterpart, abi.encodePacked(to), amount);
    }

    function test_CrosschainTransferBurnsOwnSupply() public {
        vm.startPrank(holder);
        vm.expectEmit(true, true, false, true);
        emit IBridgeFungible.CrosschainFungibleTransferSent(gateway.SEND_ID(), holder, toRecipient, AMT);
        bytes32 sendId = IBridgeFungible(diamond).crosschainTransfer(toRecipient, AMT);
        vm.stopPrank();

        assertEq(sendId, gateway.SEND_ID());
        assertEq(IERC20(diamond).balanceOf(holder), INITIAL - AMT, "burned from sender");
        assertEq(IERC20(diamond).totalSupply(), INITIAL - AMT, "supply reduced");
        assertEq(gateway.lastRecipient(), counterpart);
        assertEq(bytes4(gateway.lastPayload()), FUNGIBLE_BRIDGE_TAG);
    }

    function test_ReceiveMintsOwnSupply() public {
        vm.prank(address(gateway));
        vm.expectEmit(true, false, true, true);
        emit IBridgeFungible.CrosschainFungibleTransferReceived(RECEIVE_ID, counterpart, recipient, AMT);
        IERC7786Recipient(diamond)
            .receiveMessage(RECEIVE_ID, counterpart, bytes.concat(FUNGIBLE_BRIDGE_TAG, _inbound(recipient, AMT)));

        assertEq(IERC20(diamond).balanceOf(recipient), AMT, "minted to recipient");
        assertEq(IERC20(diamond).totalSupply(), INITIAL + AMT, "supply increased");
    }

    function test_ProcessMessageRevertsOnDirectCall() public {
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(IBridgeFungible.BridgeUnauthorizedCaller.selector, holder));
        IERC7786MessageHandler(diamond).processMessage(RECEIVE_ID, counterpart, _inbound(recipient, AMT));
    }

    function test_SupportsInterfaceBridgeFungible() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IBridgeFungible).interfaceId));
    }
}
