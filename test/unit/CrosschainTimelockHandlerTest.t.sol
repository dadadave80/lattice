// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {CrosschainTimelockHandler} from "@lattice/crosschain/CrosschainTimelockHandler.sol";
import {CrosschainLinkLib} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";
import {CROSSCHAIN_TIMELOCK_TAG} from "@lattice/crosschain/libraries/CrosschainTimelockHandlerLib.sol";
import {TimelockController} from "@lattice/governance/TimelockController.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {ICrosschainTimelockHandler} from "@lattice/interfaces/crosschain/ICrosschainTimelockHandler.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Test} from "forge-std/Test.sol";

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

/// @notice A "governance Diamond": CrosschainLink + TimelockController + the cross-chain timelock handler.
contract MockGovDiamond is AccessControl, CrosschainLink, TimelockController, CrosschainTimelockHandler {
    function initialize(address admin_, uint256 minDelay_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        address[] memory proposers = new address[](1);
        proposers[0] = address(this); // the Diamond proposes, via the authenticated cross-chain handler
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open execution
        TimelockControllerLib.__TimelockController_init(minDelay_, proposers, executors, admin_);
        CrosschainLinkLib.__CrosschainLink_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

// ---------------------------------------------------------------------------
//                              TESTS
// ---------------------------------------------------------------------------

contract CrosschainTimelockHandlerTest is Test {
    MockGovDiamond gov;
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
        gov = new MockGovDiamond();
        gov.initialize(admin, MIN_DELAY);
        gateway = new MockGateway();
        target = new MockTarget();

        counterpart = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, remoteGovernor);
        vm.startPrank(admin);
        gov.setLink(address(gateway), counterpart, false);
        gov.setHandler(CROSSCHAIN_TIMELOCK_TAG, address(gov));
        vm.stopPrank();
    }

    function _operationPayload(bytes memory callData, uint256 delay) internal view returns (bytes memory) {
        return abi.encode(address(target), uint256(0), callData, bytes32(0), SALT, delay);
    }

    function test_ReceiveSchedulesTimelockOperation() public {
        bytes memory callData = abi.encodeWithSignature("setValue(uint256)", uint256(42));
        bytes32 id = gov.hashOperation(address(target), 0, callData, bytes32(0), SALT);

        vm.prank(address(gateway));
        vm.expectEmit(true, true, false, true);
        emit ICrosschainTimelockHandler.CrosschainOperationScheduled(RECEIVE_ID, id, address(target), 0, MIN_DELAY);
        gov.receiveMessage(
            RECEIVE_ID, counterpart, bytes.concat(CROSSCHAIN_TIMELOCK_TAG, _operationPayload(callData, MIN_DELAY))
        );

        assertTrue(gov.isOperationPending(id), "operation scheduled on the timelock");
    }

    function test_ProcessMessageRevertsOnDirectCall() public {
        bytes memory op = _operationPayload(abi.encodeWithSignature("setValue(uint256)", uint256(1)), MIN_DELAY);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(ICrosschainTimelockHandler.CrosschainTimelockUnauthorizedCaller.selector, user)
        );
        gov.processMessage(RECEIVE_ID, counterpart, op);
    }

    /// @notice End-to-end cross-chain governance: an inbound message schedules a call, and after the
    ///         timelock delay anyone may execute it, mutating Diamond-controlled state.
    function test_FullCrosschainGovernanceFlow() public {
        bytes memory callData = abi.encodeWithSignature("setValue(uint256)", uint256(42));

        vm.prank(address(gateway));
        gov.receiveMessage(
            RECEIVE_ID, counterpart, bytes.concat(CROSSCHAIN_TIMELOCK_TAG, _operationPayload(callData, MIN_DELAY))
        );

        vm.warp(block.timestamp + MIN_DELAY + 1);
        gov.execute(address(target), 0, callData, bytes32(0), SALT); // open executor

        assertEq(target.value(), 42, "remote-governed call executed after delay");
    }
}
