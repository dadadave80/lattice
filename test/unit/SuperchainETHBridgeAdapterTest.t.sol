// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {SuperchainETHBridgeAdapterTestBase} from "@lattice-test/base/SuperchainETHBridgeAdapterTestBase.sol";
import {SUPERCHAIN_ETH_BRIDGE} from "@lattice/crosschain/libraries/SuperchainETHBridgeAdapterLib.sol";
import {ISuperchainETHBridgeAdapter} from "@lattice/interfaces/crosschain/ISuperchainETHBridgeAdapter.sol";

/// @notice Stand-in for the OP `SuperchainETHBridge` predeploy: records the last `sendETH` args + accepts the
///         forwarded ETH, returning a deterministic `msgHash` the adapter propagates back to the caller.
contract MockSuperchainETHBridge {
    address public lastTo;
    uint256 public lastChainId;
    uint256 public lastValue;
    uint256 public calls;

    function sendETH(address _to, uint256 _chainId) external payable returns (bytes32 msgHash_) {
        lastTo = _to;
        lastChainId = _chainId;
        lastValue = msg.value;
        ++calls;
        msgHash_ = keccak256(abi.encode(_to, _chainId, msg.value));
    }
}

/// @title SuperchainETHBridgeAdapterTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Exercises the `SuperchainETHBridge` interop adapter against a REAL diamond
///         [ERC165 + SuperchainETHBridgeAdapter]. A {MockSuperchainETHBridge} is `vm.etch`ed at the canonical
///         predeploy address so `sendETH` forwards `msg.value` to it exactly as it would on a Superchain chain.
contract SuperchainETHBridgeAdapterTest is SuperchainETHBridgeAdapterTestBase {
    ISuperchainETHBridgeAdapter internal adapter;
    address internal user = address(0xBEEF);
    address internal to = address(0xC0FFEE);
    uint256 internal constant DEST_CHAIN = 8453; // Base

    function setUp() public {
        adapter = ISuperchainETHBridgeAdapter(_deploySuperchainETHBridgeAdapter());
        // Install the predeploy stand-in at the canonical Superchain address.
        vm.etch(SUPERCHAIN_ETH_BRIDGE, address(new MockSuperchainETHBridge()).code);
        vm.deal(user, 10 ether);
    }

    function _bridge() internal pure returns (MockSuperchainETHBridge) {
        return MockSuperchainETHBridge(SUPERCHAIN_ETH_BRIDGE);
    }

    function test_BridgeReturnsPredeploy() public view {
        assertEq(adapter.bridge(), SUPERCHAIN_ETH_BRIDGE, "bridge() = canonical predeploy");
    }

    function test_SupportsInterface() public view {
        assertTrue(
            ERC165Facet(address(adapter)).supportsInterface(type(ISuperchainETHBridgeAdapter).interfaceId),
            "ISuperchainETHBridgeAdapter registered"
        );
    }

    function test_SendETHForwardsValueToPredeploy() public {
        vm.prank(user);
        bytes32 msgHash = adapter.sendETH{value: 1 ether}(to, DEST_CHAIN);

        assertEq(_bridge().calls(), 1, "predeploy called once");
        assertEq(_bridge().lastTo(), to, "recipient forwarded");
        assertEq(_bridge().lastChainId(), DEST_CHAIN, "destination chain forwarded");
        assertEq(_bridge().lastValue(), 1 ether, "exactly msg.value forwarded");
        assertEq(SUPERCHAIN_ETH_BRIDGE.balance, 1 ether, "ETH lands on the predeploy, none stuck in the diamond");
        assertEq(address(adapter).balance, 0, "diamond retains no ETH");
        assertEq(msgHash, keccak256(abi.encode(to, DEST_CHAIN, uint256(1 ether))), "msgHash propagated from predeploy");
    }

    function test_SendETHEmitsETHSent() public {
        bytes32 expectedHash = keccak256(abi.encode(to, DEST_CHAIN, uint256(0.5 ether)));
        vm.prank(user);
        vm.expectEmit(true, true, true, true, address(adapter));
        emit ISuperchainETHBridgeAdapter.ETHSent(user, to, 0.5 ether, DEST_CHAIN, expectedHash);
        adapter.sendETH{value: 0.5 ether}(to, DEST_CHAIN);
    }

    function test_SendETHRejectsZeroRecipient() public {
        vm.prank(user);
        vm.expectRevert(ISuperchainETHBridgeAdapter.InvalidRecipient.selector);
        adapter.sendETH{value: 1 ether}(address(0), DEST_CHAIN);
    }

    function test_SendETHRejectsZeroValue() public {
        vm.prank(user);
        vm.expectRevert(ISuperchainETHBridgeAdapter.ZeroValue.selector);
        adapter.sendETH{value: 0}(to, DEST_CHAIN);
    }

    /// @notice Hardening (review note): bridging to the local chain is rejected early with a clear error.
    function test_SendETHRejectsSameChain() public {
        vm.prank(user);
        vm.expectRevert(ISuperchainETHBridgeAdapter.SameChain.selector);
        adapter.sendETH{value: 1 ether}(to, block.chainid);
    }
}
