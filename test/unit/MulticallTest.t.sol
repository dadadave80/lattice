// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MulticallTestBase} from "@lattice-test/base/MulticallTestBase.sol";
import {MulticallTestFacet} from "@lattice-test/helpers/MulticallTestFacet.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {Multicall} from "@lattice/utils/Multicall.sol";

/// @title MulticallTest
/// @notice Exercises the {Multicall} facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployMulticall} script (ERC165 + AccessControl + Multicall). Every batched sub-call is a
///         `delegatecall` routed back through the diamond's OWN dispatcher, so the batch drives the co-cut
///         `AccessControl` role surface (`grantRole`/`hasRole`/`getRoleAdmin`) and the test-only
///         {MulticallTestFacet} (`currentSender`) — not a flattened inheritance mock.
contract MulticallTest is MulticallTestBase {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 private constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    Multicall internal multi; // multicall() handle on the diamond
    AccessControl internal ac; // role surface batched through multicall
    MulticallTestFacet internal senderFacet; // currentSender() handle

    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        diamond = _deployMulticall(admin);
        multi = Multicall(diamond);
        ac = AccessControl(diamond);
        senderFacet = MulticallTestFacet(diamond);
    }

    // -------------------------------------------------------------------------
    // Empty batch
    // -------------------------------------------------------------------------

    function test_EmptyBatchReturnsEmptyArray() public {
        bytes[] memory data = new bytes[](0);
        vm.prank(admin);
        bytes[] memory results = multi.multicall(data);
        assertEq(results.length, 0);
    }

    // -------------------------------------------------------------------------
    // Batch of read calls (getRoleAdmin)
    // -------------------------------------------------------------------------

    function test_BatchReadCallsReturnCorrectData() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(ac.getRoleAdmin.selector, DEFAULT_ADMIN_ROLE);
        data[1] = abi.encodeWithSelector(ac.getRoleAdmin.selector, OPERATOR_ROLE);

        bytes[] memory results = multi.multicall(data);

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
        data[0] = abi.encodeWithSelector(ac.grantRole.selector, OPERATOR_ROLE, alice);
        data[1] = abi.encodeWithSelector(ac.grantRole.selector, OPERATOR_ROLE, bob);

        vm.prank(admin);
        multi.multicall(data);

        assertTrue(ac.hasRole(OPERATOR_ROLE, alice));
        assertTrue(ac.hasRole(OPERATOR_ROLE, bob));
    }

    function test_BatchGrantRoleReturnsCorrectResultLength() public {
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(ac.grantRole.selector, OPERATOR_ROLE, alice);
        data[1] = abi.encodeWithSelector(ac.grantRole.selector, OPERATOR_ROLE, bob);

        vm.prank(admin);
        bytes[] memory results = multi.multicall(data);
        assertEq(results.length, 2);
    }

    // -------------------------------------------------------------------------
    // Failure in one call reverts the whole batch
    // -------------------------------------------------------------------------

    function test_FailureInOneBatchCallRevertsAll() public {
        bytes[] memory data = new bytes[](2);
        // First call is valid
        data[0] = abi.encodeWithSelector(ac.grantRole.selector, OPERATOR_ROLE, alice);
        // Second call will revert (nonAdmin trying to grant)
        data[1] = abi.encodeWithSelector(ac.grantRole.selector, OPERATOR_ROLE, bob);

        // Call as non-admin — the grantRole calls will fail
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE)
        );
        multi.multicall(data);

        // State should be unchanged
        assertFalse(ac.hasRole(OPERATOR_ROLE, alice));
        assertFalse(ac.hasRole(OPERATOR_ROLE, bob));
    }

    function test_RevertMidBatchUndoesAllChanges() public {
        bytes[] memory data = new bytes[](3);
        // First two calls succeed
        data[0] = abi.encodeWithSelector(ac.grantRole.selector, OPERATOR_ROLE, alice);
        data[1] = abi.encodeWithSelector(ac.grantRole.selector, OPERATOR_ROLE, bob);
        // Third call: an unrecognised selector forces the whole batch to revert.
        data[2] = abi.encodeWithSelector(bytes4(keccak256("nonExistentFunction()")));

        vm.prank(admin);
        vm.expectRevert();
        multi.multicall(data);

        // Entire batch reverted — no roles were granted
        assertFalse(ac.hasRole(OPERATOR_ROLE, alice));
        assertFalse(ac.hasRole(OPERATOR_ROLE, bob));
    }

    // -------------------------------------------------------------------------
    // Mixed read/write batch
    // -------------------------------------------------------------------------

    function test_MixedReadWriteBatch() public {
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSelector(ac.grantRole.selector, OPERATOR_ROLE, alice);
        data[1] = abi.encodeWithSelector(ac.hasRole.selector, OPERATOR_ROLE, alice);
        data[2] = abi.encodeWithSelector(ac.getRoleAdmin.selector, OPERATOR_ROLE);

        vm.prank(admin);
        bytes[] memory results = multi.multicall(data);

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
        data[0] = abi.encodeWithSelector(ac.grantRole.selector, OPERATOR_ROLE, bob);
        data[1] = abi.encodeWithSelector(senderFacet.currentSender.selector);

        vm.prank(admin);
        bytes[] memory results = multi.multicall(data);

        // bob received the role (admin was correctly recognised as the caller).
        assertTrue(ac.hasRole(OPERATOR_ROLE, bob));

        // currentSender inside the sub-call resolves to admin (the outer msg.sender).
        address resolvedSender = abi.decode(results[1], (address));
        assertEq(resolvedSender, admin, "sub-call msg.sender should be the outer caller (admin)");
    }
}
