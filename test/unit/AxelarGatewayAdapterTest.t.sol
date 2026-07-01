// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AxelarGatewayAdapter} from "@lattice/crosschain/AxelarGatewayAdapter.sol";
import {AxelarGatewayAdapterLib} from "@lattice/crosschain/libraries/AxelarGatewayAdapterLib.sol";
import {IAxelarGatewayAdapter} from "@lattice/interfaces/crosschain/IAxelarGatewayAdapter.sol";
import {IAxelarGateway} from "@lattice/interfaces/external/IAxelarGateway.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Strings} from "@lattice/utils/libraries/Strings.sol";
import {Test} from "forge-std/Test.sol";

contract MockAxelarGateway is IAxelarGateway {
    string public lastDestChain;
    string public lastContractAddr;
    bytes public lastPayload;
    bool public approve = true;

    function setApprove(bool v) external {
        approve = v;
    }

    function callContract(string calldata destChain, string calldata contractAddr, bytes calldata payload) external {
        lastDestChain = destChain;
        lastContractAddr = contractAddr;
        lastPayload = payload;
    }

    function validateContractCall(bytes32, string calldata, string calldata, bytes32) external view returns (bool) {
        return approve;
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

contract MockAxelarAdapter is AccessControl, AxelarGatewayAdapter {
    function initialize(address admin_, address gateway_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        AxelarGatewayAdapterLib.__AxelarGatewayAdapter_init(gateway_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract AxelarGatewayAdapterTest is Test {
    MockAxelarAdapter adapter;
    MockAxelarGateway axelar;
    MockRecipient recipient;

    address admin = address(0x1);
    address user = address(0x2);
    address remoteGw = address(0xA11CE);

    uint256 constant REMOTE_CHAIN = 10;
    string constant AXELAR_NAME = "optimism";

    bytes chainOnly;
    bytes remoteFull;
    string remoteGwHex;

    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        axelar = new MockAxelarGateway();
        adapter = new MockAxelarAdapter();
        adapter.initialize(admin, address(axelar));
        recipient = new MockRecipient();

        chainOnly = InteroperableAddress.formatEvmV1(REMOTE_CHAIN);
        remoteFull = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, remoteGw);
        remoteGwHex = Strings.toChecksumHexString(remoteGw);

        vm.startPrank(admin);
        adapter.registerChainEquivalence(chainOnly, AXELAR_NAME);
        adapter.registerRemoteGateway(remoteFull);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterChainEquivalence() public view {
        assertEq(adapter.getAxelarChain(chainOnly), AXELAR_NAME);
        assertEq(adapter.getErc7930Chain(AXELAR_NAME), chainOnly);
    }

    function test_RegisterChainEquivalenceRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerChainEquivalence(InteroperableAddress.formatEvmV1(99), "x");
    }

    function test_RegisterChainEquivalenceAlreadyReverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAxelarGatewayAdapter.ChainEquivalenceAlreadyRegistered.selector, chainOnly)
        );
        adapter.registerChainEquivalence(chainOnly, "other");
    }

    function test_RegisterRemoteGateway() public view {
        assertEq(adapter.getRemoteGateway(chainOnly), abi.encodePacked(remoteGw));
    }

    function test_RegisterRemoteGatewayRevertsNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        adapter.registerRemoteGateway(InteroperableAddress.formatEvmV1(99, address(0xBEEF)));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               SEND (SOURCE)
    //////////////////////////////////////////////////////////////////////////*//

    function test_SendMessageCallsAxelar() public {
        bytes memory recip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0xCAFE));
        bytes memory payload = hex"deadbeef";

        vm.prank(user);
        bytes32 sendId = adapter.sendMessage(recip, payload, new bytes[](0));

        assertEq(sendId, bytes32(0), "fire-and-forget");
        assertEq(axelar.lastDestChain(), AXELAR_NAME);
        assertEq(axelar.lastContractAddr(), remoteGwHex, "checksummed remote gateway");
        bytes memory expected = abi.encode(InteroperableAddress.formatEvmV1(block.chainid, user), recip, payload);
        assertEq(axelar.lastPayload(), expected, "adapter payload (sender, recipient, payload)");
    }

    function test_SendMessageRejectsValue() public {
        bytes memory recip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0xCAFE));
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(IAxelarGatewayAdapter.UnsupportedNativeTransfer.selector);
        adapter.sendMessage{value: 1}(recip, hex"01", new bytes[](0));
    }

    function test_SendMessageRejectsAttributes() public {
        bytes memory recip = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0xCAFE));
        bytes[] memory attrs = new bytes[](1);
        attrs[0] = hex"11223344";
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC7786GatewaySource.UnsupportedAttribute.selector, bytes4(0x11223344)));
        adapter.sendMessage(recip, hex"01", attrs);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            RECEIVE (DESTINATION)
    //////////////////////////////////////////////////////////////////////////*//

    function test_ExecuteDeliversToRecipient() public {
        bytes32 commandId = keccak256("cmd");
        bytes memory sender = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0x5151));
        bytes memory recip = InteroperableAddress.formatEvmV1(block.chainid, address(recipient));
        bytes memory payload = hex"c0ffee";

        adapter.execute(commandId, AXELAR_NAME, remoteGwHex, abi.encode(sender, recip, payload));

        assertEq(recipient.lastReceiveId(), commandId);
        assertEq(recipient.lastSender(), sender);
        assertEq(recipient.lastPayload(), payload);
    }

    function test_ExecuteRevertsWrongOriginGateway() public {
        bytes memory sender = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0x5151));
        bytes memory recip = InteroperableAddress.formatEvmV1(block.chainid, address(recipient));
        string memory wrongAddr = Strings.toChecksumHexString(address(0xDEAD));
        vm.expectRevert(
            abi.encodeWithSelector(IAxelarGatewayAdapter.InvalidOriginGateway.selector, AXELAR_NAME, wrongAddr)
        );
        adapter.execute(keccak256("cmd"), AXELAR_NAME, wrongAddr, abi.encode(sender, recip, hex"01"));
    }

    function test_ExecuteRevertsNotApproved() public {
        axelar.setApprove(false);
        bytes memory sender = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0x5151));
        bytes memory recip = InteroperableAddress.formatEvmV1(block.chainid, address(recipient));
        vm.expectRevert(IAxelarGatewayAdapter.NotApprovedByGateway.selector);
        adapter.execute(keccak256("cmd"), AXELAR_NAME, remoteGwHex, abi.encode(sender, recip, hex"01"));
    }

    function test_SupportsInterfaceGatewaySource() public view {
        assertTrue(adapter.supportsInterface(type(IERC7786GatewaySource).interfaceId));
    }
}
