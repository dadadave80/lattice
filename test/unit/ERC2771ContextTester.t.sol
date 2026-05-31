// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IERC2771Context} from "@lattice/interfaces/IERC2771Context.sol";
import {ERC2771Context} from "@lattice/utils/ERC2771Context.sol";
import {ERC2771ContextLib} from "@lattice/utils/libraries/ERC2771ContextLib.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title MockERC2771ContextContract
/// @notice Mock combining AccessControl + ERC2771Context for testing.
contract MockERC2771ContextContract is AccessControl, ERC2771Context {
    function initialize(address _admin, address _forwarder) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        ERC2771ContextLib.__ERC2771Context_init(_forwarder);
        InitializableLib.postInitializer(s);
    }

    /// @notice Returns the effective msg.sender as seen by ERC2771ContextLib.
    function whoCalledMe() external view returns (address) {
        return ERC2771ContextLib.msgSender();
    }

    /// @notice Returns the effective msg.data as seen by ERC2771ContextLib.
    function getCallData() external view returns (bytes memory) {
        return ERC2771ContextLib.msgData();
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title ERC2771ContextTester
/// @notice Comprehensive tests for ERC2771Context module.
contract ERC2771ContextTester is Test {
    MockERC2771ContextContract internal mock;

    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;

    address internal admin = address(0xA1);
    address internal alice = address(0xA11CE);
    address internal trustedForwarder = address(0xF04FADE4);
    address internal untrustedAddr = address(0xBAD);

    function setUp() public {
        mock = new MockERC2771ContextContract();
        mock.initialize(admin, trustedForwarder);
    }

    // ---- trustedForwarder / isTrustedForwarder ----

    function test_TrustedForwarderSetOnInit() public view {
        assertEq(mock.trustedForwarder(), trustedForwarder);
    }

    function test_IsTrustedForwarderReturnsTrueForSet() public view {
        assertTrue(mock.isTrustedForwarder(trustedForwarder));
    }

    function test_IsTrustedForwarderReturnsFalseForOther() public view {
        assertFalse(mock.isTrustedForwarder(untrustedAddr));
    }

    function test_ZeroAddressForwarderAllowed() public {
        MockERC2771ContextContract m = new MockERC2771ContextContract();
        m.initialize(admin, address(0));
        assertEq(m.trustedForwarder(), address(0));
        assertFalse(m.isTrustedForwarder(address(1)));
    }

    // ---- setTrustedForwarder ----

    function test_SetTrustedForwarderByAdmin() public {
        address newForwarder = address(0xFEED);
        vm.prank(admin);
        mock.setTrustedForwarder(newForwarder);
        assertEq(mock.trustedForwarder(), newForwarder);
        assertTrue(mock.isTrustedForwarder(newForwarder));
        assertFalse(mock.isTrustedForwarder(trustedForwarder));
    }

    function test_SetTrustedForwarderByNonAdminReverts() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE)
        );
        mock.setTrustedForwarder(address(0xFEED));
    }

    function test_SetTrustedForwarderToZeroSetsZeroForwarder() public {
        vm.prank(admin);
        mock.setTrustedForwarder(address(0));
        assertEq(mock.trustedForwarder(), address(0));
        // isTrustedForwarder(zero) returns true when zero is the stored forwarder
        assertTrue(mock.isTrustedForwarder(address(0)));
        // A non-zero address is still not the forwarder
        assertFalse(mock.isTrustedForwarder(address(1)));
    }

    function test_SetTrustedForwarderEmitsEvent() public {
        address newForwarder = address(0xFEED);
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit IERC2771Context.TrustedForwarderUpdated(newForwarder);
        mock.setTrustedForwarder(newForwarder);
    }

    // ---- msgSender: non-forwarded ----

    function test_NonForwardedCallReturnsMsgSender() public {
        vm.prank(alice);
        address reported = mock.whoCalledMe();
        assertEq(reported, alice);
    }

    function test_NonForwardedCallFromAdminReturnsMsgSender() public {
        vm.prank(admin);
        address reported = mock.whoCalledMe();
        assertEq(reported, admin);
    }

    // ---- msgSender: forwarded ----

    function test_ForwardedCallUnwrapsOriginalSender() public {
        address originalSender = address(0x011019);

        bytes memory data = abi.encodeWithSelector(MockERC2771ContextContract.whoCalledMe.selector);
        bytes memory dataWithSender = abi.encodePacked(data, originalSender);

        vm.prank(trustedForwarder);
        (bool ok, bytes memory ret) = address(mock).call(dataWithSender);
        assertTrue(ok);
        address reported = abi.decode(ret, (address));
        assertEq(reported, originalSender);
    }

    function test_ForwardedCallFromUntrustedReturnsActualSender() public {
        address originalSender = address(0x011019);

        bytes memory data = abi.encodeWithSelector(MockERC2771ContextContract.whoCalledMe.selector);
        bytes memory dataWithSender = abi.encodePacked(data, originalSender);

        // Call from an address that is NOT the trusted forwarder
        vm.prank(untrustedAddr);
        (bool ok, bytes memory ret) = address(mock).call(dataWithSender);
        assertTrue(ok);
        address reported = abi.decode(ret, (address));
        // Must return untrustedAddr, NOT the appended originalSender
        assertEq(reported, untrustedAddr);
    }

    function test_ForwardedCallWithInsufficientDataReturnsMsgSender() public {
        // Calldata shorter than 20 bytes — forwarder check passes but length guard fires
        // Use a bare call with only 15 bytes of data
        bytes memory shortData = new bytes(15);

        vm.prank(trustedForwarder);
        // This will likely revert (no selector match), but what matters is the lib
        // correctly falls back. Test via whoCalledMe with a forwarder that sends
        // no extra bytes (standard call, no appended sender).
        address reported = mock.whoCalledMe();
        // Plain prank: msg.sender == trustedForwarder but msg.data is the normal selector
        // which is 4 bytes < 20 — so msgSender() should fall back to msg.sender
        assertEq(reported, trustedForwarder);
    }

    // ---- msgData ----

    function test_NonForwardedMsgDataIsUnchanged() public {
        // Call getCallData without extra bytes
        bytes memory expected = abi.encodeWithSelector(MockERC2771ContextContract.getCallData.selector);
        bytes memory result = mock.getCallData();
        assertEq(result, expected);
    }

    function test_ForwardedMsgDataStripsLast20Bytes() public {
        address originalSender = address(0x011019);

        bytes memory selector = abi.encodeWithSelector(MockERC2771ContextContract.getCallData.selector);
        bytes memory dataWithSender = abi.encodePacked(selector, originalSender);

        vm.prank(trustedForwarder);
        (bool ok, bytes memory ret) = address(mock).call(dataWithSender);
        assertTrue(ok);
        bytes memory reportedData = abi.decode(ret, (bytes));
        // Should be just the selector without the appended sender
        assertEq(reportedData, selector);
    }

    // ---- ERC-165 interface registration ----

    function test_SupportsIERC2771Context() public view {
        assertTrue(mock.supportsInterface(type(IERC2771Context).interfaceId));
    }

    function test_SupportsIAccessControl() public view {
        assertTrue(mock.supportsInterface(type(IAccessControl).interfaceId));
    }

    // ---- Initialization event ----

    function test_InitEmitsTrustedForwarderUpdated() public {
        MockERC2771ContextContract m = new MockERC2771ContextContract();

        vm.recordLogs();
        m.initialize(admin, trustedForwarder);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 topic = keccak256("TrustedForwarderUpdated(address)");
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                found = true;
                break;
            }
        }
        assertTrue(found, "TrustedForwarderUpdated not emitted on init");
    }

    // ---- Update forwarder and re-verify behavior ----

    function test_UpdateForwarderChangesUnwrapBehavior() public {
        address newForwarder = address(0xEEF04AAADE4);
        address originalSender = address(0x011019);

        // Update to new forwarder
        vm.prank(admin);
        mock.setTrustedForwarder(newForwarder);

        // Old forwarder no longer unwraps
        bytes memory data = abi.encodeWithSelector(MockERC2771ContextContract.whoCalledMe.selector);
        bytes memory dataWithSender = abi.encodePacked(data, originalSender);

        vm.prank(trustedForwarder); // old forwarder
        (bool ok, bytes memory ret) = address(mock).call(dataWithSender);
        assertTrue(ok);
        address reported = abi.decode(ret, (address));
        assertEq(reported, trustedForwarder); // no unwrap

        // New forwarder does unwrap
        vm.prank(newForwarder);
        (ok, ret) = address(mock).call(dataWithSender);
        assertTrue(ok);
        reported = abi.decode(ret, (address));
        assertEq(reported, originalSender); // unwrapped
    }
}
