// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {Multicall} from "@lattice/utils/Multicall.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockMulticallContract
/// @notice Test double combining Multicall + AccessControl for batch call testing.
contract MockMulticallContract is Multicall, AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Initializes the AccessControl module.
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        InitializableLib.postInitializer(s);
    }

    /// @notice Exposes the resolved caller (`msg.sender`) for test inspection.
    function currentSender() external view returns (address) {
        return msg.sender;
    }
}

/// @title MulticallTester
/// @notice Comprehensive tests for the Multicall module.
contract MulticallTester is Test {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;

    MockMulticallContract internal mock;
    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        mock = new MockMulticallContract();
        mock.initialize(admin);
    }

    // -------------------------------------------------------------------------
    // Empty batch
    // -------------------------------------------------------------------------

    function test_EmptyBatchReturnsEmptyArray() public {
        bytes[] memory data = new bytes[](0);
        vm.prank(admin);
        bytes[] memory results = mock.multicall(data);
        assertEq(results.length, 0);
    }

    // -------------------------------------------------------------------------
    // Batch of read calls (getRoleAdmin)
    // -------------------------------------------------------------------------

    function test_BatchReadCallsReturnCorrectData() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(mock.getRoleAdmin.selector, DEFAULT_ADMIN_ROLE);
        data[1] = abi.encodeWithSelector(mock.getRoleAdmin.selector, mock.OPERATOR_ROLE());

        bytes[] memory results = mock.multicall(data);

        assertEq(results.length, 2);
        bytes32 adminOfAdmin = abi.decode(results[0], (bytes32));
        bytes32 adminOfOperator = abi.decode(results[1], (bytes32));
        assertEq(adminOfAdmin, DEFAULT_ADMIN_ROLE);
        assertEq(adminOfOperator, DEFAULT_ADMIN_ROLE);
    }

    // -------------------------------------------------------------------------
    // Batch of state-changing calls (grantRole)
    // -------------------------------------------------------------------------

    function test_BatchGrantRoleCallsAllExecute() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(mock.grantRole.selector, mock.OPERATOR_ROLE(), alice);
        data[1] = abi.encodeWithSelector(mock.grantRole.selector, mock.OPERATOR_ROLE(), bob);

        vm.prank(admin);
        mock.multicall(data);

        assertTrue(mock.hasRole(mock.OPERATOR_ROLE(), alice));
        assertTrue(mock.hasRole(mock.OPERATOR_ROLE(), bob));
    }

    function test_BatchGrantRoleReturnsCorrectResultLength() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(mock.grantRole.selector, mock.OPERATOR_ROLE(), alice);
        data[1] = abi.encodeWithSelector(mock.grantRole.selector, mock.OPERATOR_ROLE(), bob);

        vm.prank(admin);
        bytes[] memory results = mock.multicall(data);
        assertEq(results.length, 2);
    }

    // -------------------------------------------------------------------------
    // Failure in one call reverts the whole batch
    // -------------------------------------------------------------------------

    function test_FailureInOneBatchCallRevertsAll() public {
        bytes[] memory data = new bytes[](2);
        // First call is valid
        data[0] = abi.encodeWithSelector(mock.grantRole.selector, mock.OPERATOR_ROLE(), alice);
        // Second call will revert (nonAdmin trying to grant)
        data[1] = abi.encodeWithSelector(mock.grantRole.selector, mock.OPERATOR_ROLE(), bob);

        // Call as non-admin — the grantRole calls will fail
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE)
        );
        mock.multicall(data);

        // State should be unchanged
        assertFalse(mock.hasRole(mock.OPERATOR_ROLE(), alice));
        assertFalse(mock.hasRole(mock.OPERATOR_ROLE(), bob));
    }

    function test_RevertMidBatchUndoesAllChanges() public {
        bytes[] memory data = new bytes[](3);
        // First two calls succeed
        data[0] = abi.encodeWithSelector(mock.grantRole.selector, mock.OPERATOR_ROLE(), alice);
        data[1] = abi.encodeWithSelector(mock.grantRole.selector, mock.OPERATOR_ROLE(), bob);
        // Third call: an unrecognised selector forces the whole batch to revert.
        data[2] = abi.encodeWithSelector(bytes4(keccak256("nonExistentFunction()")));

        vm.prank(admin);
        vm.expectRevert();
        mock.multicall(data);

        // Entire batch reverted — no roles were granted
        assertFalse(mock.hasRole(mock.OPERATOR_ROLE(), alice));
        assertFalse(mock.hasRole(mock.OPERATOR_ROLE(), bob));
    }

    // -------------------------------------------------------------------------
    // Mixed read/write batch
    // -------------------------------------------------------------------------

    function test_MixedReadWriteBatch() public {
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSelector(mock.grantRole.selector, mock.OPERATOR_ROLE(), alice);
        data[1] = abi.encodeWithSelector(mock.hasRole.selector, mock.OPERATOR_ROLE(), alice);
        data[2] = abi.encodeWithSelector(mock.getRoleAdmin.selector, mock.OPERATOR_ROLE());

        vm.prank(admin);
        bytes[] memory results = mock.multicall(data);

        assertEq(results.length, 3);
        // result[1] should be true (alice now has the role after call[0])
        bool aliceHasRole = abi.decode(results[1], (bool));
        assertTrue(aliceHasRole);
        bytes32 roleAdmin = abi.decode(results[2], (bytes32));
        assertEq(roleAdmin, DEFAULT_ADMIN_ROLE);
    }

    // -------------------------------------------------------------------------
    // Caller resolution: delegatecall sub-calls preserve the outer msg.sender
    // -------------------------------------------------------------------------

    /// @notice Each sub-call is a `delegatecall`, so access-controlled sub-calls see the original
    ///         caller and `msg.sender` resolves to the outer caller throughout the batch.
    function test_MulticallSubcallsSeeOriginalSender() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(mock.grantRole.selector, mock.OPERATOR_ROLE(), bob);
        data[1] = abi.encodeWithSelector(mock.currentSender.selector);

        vm.prank(admin);
        bytes[] memory results = mock.multicall(data);

        // bob received the role (admin was correctly recognised as the caller).
        assertTrue(mock.hasRole(mock.OPERATOR_ROLE(), bob));

        // currentSender inside the sub-call resolves to admin (the outer msg.sender).
        address resolvedSender = abi.decode(results[1], (address));
        assertEq(resolvedSender, admin, "sub-call msg.sender should be the outer caller (admin)");
    }
}
