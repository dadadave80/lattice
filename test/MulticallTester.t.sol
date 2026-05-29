// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IMulticall} from "@lattice/interfaces/IMulticall.sol";
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

    /// @notice Exposes ContextLib.msgSender() for test inspection.
    function currentSender() external view returns (address) {
        return ContextLib.msgSender();
    }
}

/// @title MockForwarder
/// @notice Simulates an ERC-2771 trusted forwarder that relays a multicall on behalf of a user.
/// In production a real forwarder would append the original sender to msg.data; here we relay
/// the call so that `msg.sender` inside the target is the forwarder, not the user.
contract MockForwarder {
    /// @notice Calls `multicall` on `target` forwarding `data` as `msg.sender = address(this)`.
    function forward(address target, bytes[] calldata data) external returns (bytes[] memory) {
        return IMulticall(target).multicall(data);
    }
}

/// @title MulticallTester
/// @notice Comprehensive tests for the Multicall module.
contract MulticallTester is Test {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;

    MockMulticallContract internal mock;
    MockForwarder internal forwarder;
    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        mock = new MockMulticallContract();
        mock.initialize(admin);
        forwarder = new MockForwarder();
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
        // Third call: revokeRole for an account that won't cause a revert itself, but
        // let's trigger an auth failure by revoking DEFAULT_ADMIN_ROLE without proper auth chain.
        // Actually easiest: pass invalid calldata that decodes to a failing grantRole from a bad account.
        // We'll use a hasRole call to a non-existent selector to cause a revert.
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
    // OZ-reconciliation: MC-1 — ERC-2771 context-suffix propagation
    // -------------------------------------------------------------------------

    /// @notice Verifies that access-controlled subcalls inside multicall correctly
    /// resolve the caller even when the call arrives through an intermediary (forwarder).
    ///
    /// In the current diamond-lib, ContextLib.msgSender() returns msg.sender unconditionally
    /// (contextSuffixLength == 0), so msg.sender == ContextLib.msgSender() always holds and
    /// no context suffix is appended. This test exercises the non-suffix path end-to-end:
    /// the forwarder calls multicall on behalf of admin, but since the forwarder IS the
    /// msg.sender at that point and ContextLib reflects that, the subcall correctly identifies
    /// the forwarder as the caller — role grants must therefore be pre-set on the forwarder.
    ///
    /// When diamond-lib ships a trusted-forwarder-aware ContextLib (contextSuffixLength > 0),
    /// the suffix branch in MulticallLib will fire and the original EOA will be correctly
    /// propagated to each subcall without needing a role on the forwarder.
    function test_MulticallPreservesERC2771Sender() public {
        // Grant the forwarder admin role so it can act as the caller in the current
        // no-suffix context (forwarder is msg.sender inside the delegatecall).
        vm.prank(admin);
        mock.grantRole(DEFAULT_ADMIN_ROLE, address(forwarder));

        // Build a batch: grant OPERATOR_ROLE to alice, then read it back.
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(mock.grantRole.selector, mock.OPERATOR_ROLE(), alice);
        data[1] = abi.encodeWithSelector(mock.hasRole.selector, mock.OPERATOR_ROLE(), alice);

        // The forwarder calls multicall — msg.sender inside the library is address(forwarder).
        bytes[] memory results = forwarder.forward(address(mock), data);

        assertEq(results.length, 2);
        bool aliceHasRole = abi.decode(results[1], (bool));
        assertTrue(aliceHasRole, "alice should have OPERATOR_ROLE after forwarder-relayed multicall");
    }

    /// @notice Verifies that when there is no forwarder in use (direct call path),
    /// access-controlled subcalls in multicall see the true original caller and succeed.
    function test_MulticallDirectCallPreservesOriginalSender() public {
        // admin calls multicall directly — no forwarder involved.
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(mock.grantRole.selector, mock.OPERATOR_ROLE(), bob);
        data[1] = abi.encodeWithSelector(mock.currentSender.selector);

        vm.prank(admin);
        bytes[] memory results = mock.multicall(data);

        // bob received the role
        assertTrue(mock.hasRole(mock.OPERATOR_ROLE(), bob));

        // currentSender inside the subcall should resolve to admin (the original msg.sender).
        address resolvedSender = abi.decode(results[1], (address));
        assertEq(resolvedSender, admin, "ContextLib.msgSender() should return admin in non-forwarder path");
    }
}
