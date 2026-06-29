// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {FUNGIBLE_BRIDGE_TAG} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {CrosschainLinkLib} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";
import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Crosschain} from "@lattice/tokens/ERC20/ERC20Crosschain.sol";
import {ERC20CrosschainLib} from "@lattice/tokens/ERC20/libraries/ERC20CrosschainLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Test} from "forge-std/Test.sol";

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

/// @notice A self-bridging token: ERC20 + CrosschainLink + ERC20Crosschain in one Diamond.
contract MockERC20CrosschainToken is AccessControl, ERC20, CrosschainLink, ERC20Crosschain {
    function initialize(address admin_, address holder, uint256 supply) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        ERC20Lib.__ERC20_init("Lattice Omni", "lOMNI");
        CrosschainLinkLib.__CrosschainLink_init();
        ERC20CrosschainLib.__ERC20Crosschain_init();
        if (holder != address(0) && supply > 0) ERC20Lib._mint(holder, supply);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract ERC20CrosschainTester is Test {
    MockERC20CrosschainToken token;
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
        token = new MockERC20CrosschainToken();
        token.initialize(admin, holder, INITIAL);
        gateway = new MockGateway();

        counterpart = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, remotePeer);
        toRecipient = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, recipient);

        vm.startPrank(admin);
        token.setLink(address(gateway), counterpart, false);
        token.setHandler(FUNGIBLE_BRIDGE_TAG, address(token));
        vm.stopPrank();
    }

    function _inbound(address to, uint256 amount) internal view returns (bytes memory) {
        return abi.encode(counterpart, abi.encodePacked(to), amount);
    }

    function test_CrosschainTransferBurnsOwnSupply() public {
        vm.startPrank(holder);
        vm.expectEmit(true, true, false, true);
        emit IBridgeFungible.CrosschainFungibleTransferSent(gateway.SEND_ID(), holder, toRecipient, AMT);
        bytes32 sendId = token.crosschainTransfer(toRecipient, AMT);
        vm.stopPrank();

        assertEq(sendId, gateway.SEND_ID());
        assertEq(IERC20(address(token)).balanceOf(holder), INITIAL - AMT, "burned from sender");
        assertEq(IERC20(address(token)).totalSupply(), INITIAL - AMT, "supply reduced");
        assertEq(gateway.lastRecipient(), counterpart);
        assertEq(bytes4(gateway.lastPayload()), FUNGIBLE_BRIDGE_TAG);
    }

    function test_ReceiveMintsOwnSupply() public {
        vm.prank(address(gateway));
        vm.expectEmit(true, false, true, true);
        emit IBridgeFungible.CrosschainFungibleTransferReceived(RECEIVE_ID, counterpart, recipient, AMT);
        token.receiveMessage(RECEIVE_ID, counterpart, bytes.concat(FUNGIBLE_BRIDGE_TAG, _inbound(recipient, AMT)));

        assertEq(IERC20(address(token)).balanceOf(recipient), AMT, "minted to recipient");
        assertEq(IERC20(address(token)).totalSupply(), INITIAL + AMT, "supply increased");
    }

    function test_ProcessMessageRevertsOnDirectCall() public {
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(IBridgeFungible.BridgeUnauthorizedCaller.selector, holder));
        token.processMessage(RECEIVE_ID, counterpart, _inbound(recipient, AMT));
    }

    function test_SupportsInterfaceBridgeFungible() public view {
        assertTrue(token.supportsInterface(type(IBridgeFungible).interfaceId));
    }
}
