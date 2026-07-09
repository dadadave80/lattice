// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CrosschainTimelockHandlerTestBase} from "@lattice-test/base/CrosschainTimelockHandlerTestBase.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {CrosschainTimelockHandler} from "@lattice/crosschain/CrosschainTimelockHandler.sol";
import {CROSSCHAIN_TIMELOCK_TAG} from "@lattice/crosschain/libraries/CrosschainTimelockHandlerLib.sol";
import {TimelockController} from "@lattice/governance/TimelockController.sol";
import {ICrosschainTimelockHandler} from "@lattice/interfaces/crosschain/ICrosschainTimelockHandler.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

// ---------------------------------------------------------------------------
//                              MOCKS
// ---------------------------------------------------------------------------

contract MockGateway is IERC7786GatewaySource {
    function supportsAttribute(bytes4) external pure returns (bool) {
        return false;
    }

    function sendMessage(bytes calldata, bytes calldata, bytes[] calldata) external payable returns (bytes32) {
        return bytes32(uint256(1));
    }
}

/// @notice Target of the timelocked operation.
contract MockTarget {
    uint256 public value;

    function setValue(uint256 v) external {
        value = v;
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

contract CrosschainTimelockHandlerTest is CrosschainTimelockHandlerTestBase {
    address internal diamond; // the assembled cross-chain governance diamond
    CrosschainLink link; // typed handle for the messaging registry
    TimelockController timelock; // typed handle for the co-mounted timelock
    CrosschainTimelockHandler handler; // typed handle for the cross-chain handler
    MockGateway gateway;
    MockTarget target;

    address admin = address(0x1);
    address user = address(0x2);
    address remoteGovernor = address(0x6041);

    uint256 constant REMOTE_CHAIN = 10;
    uint256 constant MIN_DELAY = 2 days;
    bytes32 constant RECEIVE_ID = keccak256("gov-msg-1");
    bytes32 constant SALT = keccak256("op-salt");

    bytes counterpart;

    function setUp() public {
        vm.warp(1_000_000); // non-zero base time
        diamond = _deployCrosschainTimelockHandler(admin, MIN_DELAY);
        link = CrosschainLink(diamond);
        timelock = TimelockController(payable(diamond));
        handler = CrosschainTimelockHandler(diamond);
        gateway = new MockGateway();
        target = new MockTarget();

        counterpart = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, remoteGovernor);
        vm.startPrank(admin);
        link.setLink(address(gateway), counterpart, false);
        link.setHandler(CROSSCHAIN_TIMELOCK_TAG, address(diamond));
        vm.stopPrank();
    }

    function _operationPayload(bytes memory callData, uint256 delay) internal view returns (bytes memory) {
        return abi.encode(address(target), uint256(0), callData, bytes32(0), SALT, delay);
    }

    function test_ReceiveSchedulesTimelockOperation() public {
        bytes memory callData = abi.encodeWithSignature("setValue(uint256)", uint256(42));
        bytes32 id = timelock.hashOperation(address(target), 0, callData, bytes32(0), SALT);

        vm.prank(address(gateway));
        vm.expectEmit(true, true, false, true);
        emit ICrosschainTimelockHandler.CrosschainOperationScheduled(RECEIVE_ID, id, address(target), 0, MIN_DELAY);
        link.receiveMessage(
            RECEIVE_ID, counterpart, bytes.concat(CROSSCHAIN_TIMELOCK_TAG, _operationPayload(callData, MIN_DELAY))
        );

        assertTrue(timelock.isOperationPending(id), "operation scheduled on the timelock");
    }

    function test_ProcessMessageRevertsOnDirectCall() public {
        bytes memory op = _operationPayload(abi.encodeWithSignature("setValue(uint256)", uint256(1)), MIN_DELAY);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ICrosschainTimelockHandler.CrosschainTimelockUnauthorizedCaller.selector, user)
        );
        handler.processMessage(RECEIVE_ID, counterpart, op);
    }

    /// @notice End-to-end cross-chain governance: an inbound message schedules a call, and after the
    ///         timelock delay anyone may execute it, mutating Diamond-controlled state.
    function test_FullCrosschainGovernanceFlow() public {
        bytes memory callData = abi.encodeWithSignature("setValue(uint256)", uint256(42));

        vm.prank(address(gateway));
        link.receiveMessage(
            RECEIVE_ID, counterpart, bytes.concat(CROSSCHAIN_TIMELOCK_TAG, _operationPayload(callData, MIN_DELAY))
        );

        vm.warp(block.timestamp + MIN_DELAY + 1);
        timelock.execute(address(target), 0, callData, bytes32(0), SALT); // open executor

        assertEq(target.value(), 42, "remote-governed call executed after delay");
    }
}
