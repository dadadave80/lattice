// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IRateLimiter} from "@lattice/interfaces/IRateLimiter.sol";
import {RateLimiter} from "@lattice/security/RateLimiter.sol";
import {RateLimiterLib} from "@lattice/security/libraries/RateLimiterLib.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockRateLimiterContract
/// @notice Test double combining RateLimiter + AccessControl.
contract MockRateLimiterContract is RateLimiter, AccessControl {
    /// @notice Initializes both AccessControl and RateLimiter modules.
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        RateLimiterLib.__RateLimiter_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title RateLimiterTester
/// @notice Comprehensive tests for the RateLimiter module.
contract RateLimiterTester is Test {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 private constant KEY_A = keccak256("KEY_A");
    bytes32 private constant KEY_B = keccak256("KEY_B");

    MockRateLimiterContract internal mock;
    address internal admin = address(0xA1);
    address internal nonAdmin = address(0xB2);
    address internal user = address(0xC3);

    function setUp() public {
        mock = new MockRateLimiterContract();
        mock.initialize(admin);
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    function test_ERC165RegisteredIRateLimiter() public view {
        assertTrue(mock.supportsInterface(type(IRateLimiter).interfaceId));
    }

    // -------------------------------------------------------------------------
    // configure — access control
    // -------------------------------------------------------------------------

    function test_ConfigureByNonAdminReverts() public {
        vm.prank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, DEFAULT_ADMIN_ROLE
            )
        );
        mock.configure(KEY_A, 100, 10);
    }

    // -------------------------------------------------------------------------
    // configure — invalid params
    // -------------------------------------------------------------------------

    function test_ConfigureWithZeroCapacityReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitInvalidConfig.selector));
        mock.configure(KEY_A, 0, 10);
    }

    function test_ConfigureWithZeroRefillRateReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitInvalidConfig.selector));
        mock.configure(KEY_A, 100, 0);
    }

    // -------------------------------------------------------------------------
    // configure — happy path
    // -------------------------------------------------------------------------

    function test_ConfigureStoresValues() public {
        vm.prank(admin);
        mock.configure(KEY_A, 500, 25);

        (uint256 cap, uint256 rate) = mock.getConfig(KEY_A);
        assertEq(cap, 500);
        assertEq(rate, 25);
    }

    function test_ConfigureEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IRateLimiter.RateLimitConfigured(KEY_A, 500, 25);
        mock.configure(KEY_A, 500, 25);
    }

    function test_ConfigureSetsTokensToCapacity() public {
        vm.prank(admin);
        mock.configure(KEY_A, 1000, 10);

        assertEq(mock.getAvailable(KEY_A), 1000);
    }

    // -------------------------------------------------------------------------
    // consume — zero amount
    // -------------------------------------------------------------------------

    function test_ConsumeZeroAmountReverts() public {
        vm.prank(admin);
        mock.configure(KEY_A, 100, 10);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitInvalidAmount.selector));
        mock.consume(KEY_A, 0);
    }

    // -------------------------------------------------------------------------
    // consume — unconfigured key
    // -------------------------------------------------------------------------

    function test_ConsumeOnUnconfiguredKeyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitNotConfigured.selector, KEY_A));
        mock.consume(KEY_A, 1);
    }

    // -------------------------------------------------------------------------
    // consume — within capacity
    // -------------------------------------------------------------------------

    function test_ConsumeWithinCapacitySucceeds() public {
        vm.prank(admin);
        mock.configure(KEY_A, 100, 10);

        vm.prank(user);
        mock.consume(KEY_A, 50);

        assertEq(mock.getAvailable(KEY_A), 50);
    }

    function test_ConsumeEmitsEvent() public {
        vm.prank(admin);
        mock.configure(KEY_A, 100, 10);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit IRateLimiter.RateLimitConsumed(KEY_A, user, 50, 50);
        mock.consume(KEY_A, 50);
    }

    // -------------------------------------------------------------------------
    // consume — exceeds capacity
    // -------------------------------------------------------------------------

    function test_ConsumeExceedingCapacityReverts() public {
        vm.prank(admin);
        mock.configure(KEY_A, 100, 10);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitExceeded.selector, KEY_A, 101, 100));
        mock.consume(KEY_A, 101);
    }

    function test_ConsumeExceedingRemainingReverts() public {
        vm.prank(admin);
        mock.configure(KEY_A, 100, 10);

        vm.prank(user);
        mock.consume(KEY_A, 90); // leaves 10

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitExceeded.selector, KEY_A, 20, 10));
        mock.consume(KEY_A, 20);
    }

    // -------------------------------------------------------------------------
    // refill over time
    // -------------------------------------------------------------------------

    function test_RefillHappensOverTime() public {
        vm.prank(admin);
        mock.configure(KEY_A, 100, 10); // 10 tokens/second

        vm.prank(user);
        mock.consume(KEY_A, 100); // drain fully
        assertEq(mock.getAvailable(KEY_A), 0);

        // Warp 5 seconds → 50 tokens refilled
        vm.warp(block.timestamp + 5);

        assertEq(mock.getAvailable(KEY_A), 50);
    }

    function test_RefillCapsAtCapacity() public {
        vm.prank(admin);
        mock.configure(KEY_A, 100, 10);

        vm.prank(user);
        mock.consume(KEY_A, 50); // leaves 50

        // Warp a long time — should cap at 100 not exceed
        vm.warp(block.timestamp + 1000);

        assertEq(mock.getAvailable(KEY_A), 100);
    }

    function test_ConsumeAfterRefillSucceeds() public {
        vm.prank(admin);
        mock.configure(KEY_A, 100, 10);

        vm.prank(user);
        mock.consume(KEY_A, 100); // drain

        vm.warp(block.timestamp + 10); // refill 100 tokens

        // Now should succeed again.
        vm.prank(user);
        mock.consume(KEY_A, 100);

        assertEq(mock.getAvailable(KEY_A), 0);
    }

    // -------------------------------------------------------------------------
    // getAvailable — does not mutate state
    // -------------------------------------------------------------------------

    function test_GetAvailableDoesNotMutateState() public {
        vm.prank(admin);
        mock.configure(KEY_A, 100, 10);

        vm.prank(user);
        mock.consume(KEY_A, 60); // leaves 40

        vm.warp(block.timestamp + 3); // would refill 30 → 70 if persisted

        // Multiple getAvailable calls — state should not change
        uint256 a1 = mock.getAvailable(KEY_A);
        uint256 a2 = mock.getAvailable(KEY_A);
        assertEq(a1, a2);
        assertEq(a1, 70);

        // Actual consume should still see 70.
        vm.prank(user);
        mock.consume(KEY_A, 70);
        assertEq(mock.getAvailable(KEY_A), 0);
    }

    // -------------------------------------------------------------------------
    // refill saturation — overflow safety
    // -------------------------------------------------------------------------

    function test_RefillSaturatesAtCapacityNeverOverflows() public {
        // Large refillRate: capacity / refillRate < elapsed would overflow without saturation.
        uint256 hugeRate = type(uint256).max / 100;
        vm.prank(admin);
        mock.configure(KEY_A, 1000, hugeRate);

        // Drain fully.
        vm.prank(user);
        mock.consume(KEY_A, 1000);

        // Warp 200 seconds — elapsed * hugeRate >> capacity, would overflow without saturation.
        vm.warp(block.timestamp + 200);

        // Must not revert; must return exactly capacity (saturated).
        uint256 available = mock.getAvailable(KEY_A);
        assertEq(available, 1000);
    }

    // -------------------------------------------------------------------------
    // independent keys
    // -------------------------------------------------------------------------

    function test_IndependentKeys() public {
        vm.prank(admin);
        mock.configure(KEY_A, 100, 10);
        vm.prank(admin);
        mock.configure(KEY_B, 500, 50);

        vm.prank(user);
        mock.consume(KEY_A, 100); // drain KEY_A

        // KEY_B should be unaffected
        assertEq(mock.getAvailable(KEY_B), 500);
    }
}
