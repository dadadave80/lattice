// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {RateLimiterTestBase} from "@lattice-test/base/RateLimiterTestBase.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IRateLimiter} from "@lattice/interfaces/security/IRateLimiter.sol";
import {RateLimiter} from "@lattice/security/RateLimiter.sol";

/// @title RateLimiterTest
/// @notice Exercises the RateLimiter facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployRateLimiter} script (see {RateLimiterTestBase}) — every call below routes through the diamond's
///         `delegatecall` dispatch, not a flattened inheritance mock. Admin gating on `configure` is enforced by
///         the cut-in `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`.
contract RateLimiterTest is RateLimiterTestBase {
    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 private constant KEY_A = keccak256("KEY_A");
    bytes32 private constant KEY_B = keccak256("KEY_B");

    address internal admin = address(0xA1);
    address internal nonAdmin = address(0xB2);
    address internal user = address(0xC3);

    function setUp() public {
        diamond = _deployRateLimiter(admin);
        limiter = RateLimiter(diamond);
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    function test_ERC165RegisteredIRateLimiter() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IRateLimiter).interfaceId));
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
        limiter.configure(KEY_A, 100, 10);
    }

    // -------------------------------------------------------------------------
    // configure — invalid params
    // -------------------------------------------------------------------------

    function test_ConfigureWithZeroCapacityReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitInvalidConfig.selector));
        limiter.configure(KEY_A, 0, 10);
    }

    function test_ConfigureWithZeroRefillRateReverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitInvalidConfig.selector));
        limiter.configure(KEY_A, 100, 0);
    }

    // -------------------------------------------------------------------------
    // configure — happy path
    // -------------------------------------------------------------------------

    function test_ConfigureStoresValues() public {
        vm.prank(admin);
        limiter.configure(KEY_A, 500, 25);

        (uint256 cap, uint256 rate) = limiter.getConfig(KEY_A);
        assertEq(cap, 500);
        assertEq(rate, 25);
    }

    function test_ConfigureEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IRateLimiter.RateLimitConfigured(KEY_A, 500, 25);
        limiter.configure(KEY_A, 500, 25);
    }

    function test_ConfigureSetsTokensToCapacity() public {
        vm.prank(admin);
        limiter.configure(KEY_A, 1000, 10);

        assertEq(limiter.getAvailable(KEY_A), 1000);
    }

    // -------------------------------------------------------------------------
    // consume — zero amount
    // -------------------------------------------------------------------------

    function test_ConsumeZeroAmountReverts() public {
        vm.prank(admin);
        limiter.configure(KEY_A, 100, 10);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitInvalidAmount.selector));
        limiter.consume(KEY_A, 0);
    }

    // -------------------------------------------------------------------------
    // consume — unconfigured key
    // -------------------------------------------------------------------------

    function test_ConsumeOnUnconfiguredKeyReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitNotConfigured.selector, KEY_A));
        limiter.consume(KEY_A, 1);
    }

    // -------------------------------------------------------------------------
    // consume — within capacity
    // -------------------------------------------------------------------------

    function test_ConsumeWithinCapacitySucceeds() public {
        vm.prank(admin);
        limiter.configure(KEY_A, 100, 10);

        vm.prank(user);
        limiter.consume(KEY_A, 50);

        assertEq(limiter.getAvailable(KEY_A), 50);
    }

    function test_ConsumeEmitsEvent() public {
        vm.prank(admin);
        limiter.configure(KEY_A, 100, 10);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit IRateLimiter.RateLimitConsumed(KEY_A, user, 50, 50);
        limiter.consume(KEY_A, 50);
    }

    // -------------------------------------------------------------------------
    // consume — exceeds capacity
    // -------------------------------------------------------------------------

    function test_ConsumeExceedingCapacityReverts() public {
        vm.prank(admin);
        limiter.configure(KEY_A, 100, 10);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitExceeded.selector, KEY_A, 101, 100));
        limiter.consume(KEY_A, 101);
    }

    function test_ConsumeExceedingRemainingReverts() public {
        vm.prank(admin);
        limiter.configure(KEY_A, 100, 10);

        vm.prank(user);
        limiter.consume(KEY_A, 90); // leaves 10

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IRateLimiter.RateLimitExceeded.selector, KEY_A, 20, 10));
        limiter.consume(KEY_A, 20);
    }

    // -------------------------------------------------------------------------
    // refill over time
    // -------------------------------------------------------------------------

    function test_RefillHappensOverTime() public {
        vm.prank(admin);
        limiter.configure(KEY_A, 100, 10); // 10 tokens/second

        vm.prank(user);
        limiter.consume(KEY_A, 100); // drain fully
        assertEq(limiter.getAvailable(KEY_A), 0);

        // Warp 5 seconds → 50 tokens refilled
        vm.warp(block.timestamp + 5);

        assertEq(limiter.getAvailable(KEY_A), 50);
    }

    function test_RefillCapsAtCapacity() public {
        vm.prank(admin);
        limiter.configure(KEY_A, 100, 10);

        vm.prank(user);
        limiter.consume(KEY_A, 50); // leaves 50

        // Warp a long time — should cap at 100 not exceed
        vm.warp(block.timestamp + 1000);

        assertEq(limiter.getAvailable(KEY_A), 100);
    }

    function test_ConsumeAfterRefillSucceeds() public {
        vm.prank(admin);
        limiter.configure(KEY_A, 100, 10);

        vm.prank(user);
        limiter.consume(KEY_A, 100); // drain

        vm.warp(block.timestamp + 10); // refill 100 tokens

        // Now should succeed again.
        vm.prank(user);
        limiter.consume(KEY_A, 100);

        assertEq(limiter.getAvailable(KEY_A), 0);
    }

    // -------------------------------------------------------------------------
    // getAvailable — does not mutate state
    // -------------------------------------------------------------------------

    function test_GetAvailableDoesNotMutateState() public {
        vm.prank(admin);
        limiter.configure(KEY_A, 100, 10);

        vm.prank(user);
        limiter.consume(KEY_A, 60); // leaves 40

        vm.warp(block.timestamp + 3); // would refill 30 → 70 if persisted

        // Multiple getAvailable calls — state should not change
        uint256 a1 = limiter.getAvailable(KEY_A);
        uint256 a2 = limiter.getAvailable(KEY_A);
        assertEq(a1, a2);
        assertEq(a1, 70);

        // Actual consume should still see 70.
        vm.prank(user);
        limiter.consume(KEY_A, 70);
        assertEq(limiter.getAvailable(KEY_A), 0);
    }

    // -------------------------------------------------------------------------
    // refill saturation — overflow safety
    // -------------------------------------------------------------------------

    function test_RefillSaturatesAtCapacityNeverOverflows() public {
        // Large refillRate: capacity / refillRate < elapsed would overflow without saturation.
        uint256 hugeRate = type(uint256).max / 100;
        vm.prank(admin);
        limiter.configure(KEY_A, 1000, hugeRate);

        // Drain fully.
        vm.prank(user);
        limiter.consume(KEY_A, 1000);

        // Warp 200 seconds — elapsed * hugeRate >> capacity, would overflow without saturation.
        vm.warp(block.timestamp + 200);

        // Must not revert; must return exactly capacity (saturated).
        uint256 available = limiter.getAvailable(KEY_A);
        assertEq(available, 1000);
    }

    // -------------------------------------------------------------------------
    // independent keys
    // -------------------------------------------------------------------------

    function test_IndependentKeys() public {
        vm.prank(admin);
        limiter.configure(KEY_A, 100, 10);
        vm.prank(admin);
        limiter.configure(KEY_B, 500, 50);

        vm.prank(user);
        limiter.consume(KEY_A, 100); // drain KEY_A

        // KEY_B should be unaffected
        assertEq(limiter.getAvailable(KEY_B), 500);
    }
}
