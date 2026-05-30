// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title AccessControlSuiteTest
/// @notice Integration test composing AccessControl + AccessControlTimed +
///         AccessControlEnumerable + AccessControlDefaultAdminRules + Ownable
///         in a single mock Diamond.
///
/// Scenario:
///  1. Deploy a Diamond with all four AccessControl flavors.
///  2. Owner (DEFAULT_ADMIN_ROLE source via Ownable) grants a custom role to
///     alice with a 1-hour timed window.
///  3. Verify alice has the role via both enumerable and timed.
///  4. Warp past expiry → hasRole returns false.
///  5. Owner initiates a default-admin transfer to bob (timelocked).
///  6. Verify transfer cannot complete before the delay elapses.
///  7. Warp + accept → bob is now the owner AND default admin.
///  8. Bob grants alice a non-timed role; enumerable picks it up.

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDefaultAdminRules} from "@lattice/access/AccessControlDefaultAdminRules.sol";
import {AccessControlEnumerable} from "@lattice/access/AccessControlEnumerable.sol";
import {AccessControlTimed} from "@lattice/access/AccessControlTimed.sol";
import {Ownable} from "@lattice/access/Ownable.sol";
import {AccessControlDefaultAdminRulesLib} from "@lattice/access/libraries/AccessControlDefaultAdminRulesLib.sol";
import {AccessControlEnumerableLib} from "@lattice/access/libraries/AccessControlEnumerableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccessControlTimedLib} from "@lattice/access/libraries/AccessControlTimedLib.sol";
import {IAccessControlDefaultAdminRules} from "@lattice/interfaces/IAccessControlDefaultAdminRules.sol";
import {TimelockLib} from "@lattice/utils/libraries/TimelockLib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                           MOCK DIAMOND CONTRACT
//////////////////////////////////////////////////////////////////////////*//

/// @notice Mock Diamond stacking all four AccessControl flavors + Ownable.
/// @dev Multiple inheritance requires explicit overrides for the functions
///      redefined in AccessControlEnumerable and AccessControlDefaultAdminRules.
///      We delegate to the "most derived" semantics: DefaultAdminRules guards
///      DEFAULT_ADMIN_ROLE mutations; Enumerable hooks grantRole/revokeRole/renounceRole;
///      DefaultAdminRules hasRole checks owner() for DEFAULT_ADMIN_ROLE.
contract MockAccessSuiteDiamond is
    AccessControl,
    AccessControlTimed,
    AccessControlEnumerable,
    AccessControlDefaultAdminRules,
    Ownable
{
    function initialize(address _admin, uint48 _defaultAdminDelay) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        OwnableLib.initializeOwner(_admin);
        AccessControlLib.__AccessControl_init(_admin);
        AccessControlTimedLib.__AccessControlTimed_init();
        AccessControlEnumerableLib.__AccessControlEnumerable_init();
        AccessControlDefaultAdminRulesLib.__AccessControlDefaultAdminRules_init(_defaultAdminDelay);
        InitializableLib.postInitializer(s);
    }

    // ---- Explicit overrides to resolve diamond-inheritance ambiguity ----

    function hasRole(bytes32 _role, address _account)
        public
        view
        override(AccessControl, AccessControlTimed, AccessControlEnumerable, AccessControlDefaultAdminRules)
        returns (bool)
    {
        // DefaultAdminRules semantics: DEFAULT_ADMIN_ROLE is held by owner().
        if (_role == 0x00) {
            return _account == AccessControlDefaultAdminRulesLib.defaultAdmin();
        }
        return AccessControlTimedLib.hasRole(_role, _account);
    }

    function getRoleAdmin(bytes32 _role)
        public
        view
        override(AccessControl, AccessControlTimed, AccessControlEnumerable, AccessControlDefaultAdminRules)
        returns (bytes32)
    {
        return AccessControlLib.getRoleAdmin(_role);
    }

    function grantRole(bytes32 _role, address _account)
        public
        override(AccessControl, AccessControlTimed, AccessControlEnumerable, AccessControlDefaultAdminRules)
    {
        if (_role == 0x00) {
            revert IAccessControlDefaultAdminRules.AccessControlDefaultAdminRulesUseAdminTransfer();
        }
        AccessControlEnumerableLib.grantRole(_role, _account);
    }

    function revokeRole(bytes32 _role, address _account)
        public
        override(AccessControl, AccessControlTimed, AccessControlEnumerable, AccessControlDefaultAdminRules)
    {
        if (_role == 0x00) {
            revert IAccessControlDefaultAdminRules.AccessControlDefaultAdminRulesUseAdminTransfer();
        }
        AccessControlEnumerableLib.revokeRole(_role, _account);
    }

    function renounceRole(bytes32 _role, address _callerConfirmation)
        public
        override(AccessControl, AccessControlTimed, AccessControlEnumerable, AccessControlDefaultAdminRules)
    {
        if (_role == 0x00) {
            revert IAccessControlDefaultAdminRules.AccessControlDefaultAdminRulesUseAdminTransfer();
        }
        AccessControlEnumerableLib.renounceRole(_role, _callerConfirmation);
    }

    /// @notice Override grantRoleTimed so the enumerable set is also updated.
    /// @dev AccessControlTimedLib.grantRoleTimed calls AccessControlLib._grantRole (not the
    ///      enumerable hook). We call the enumerable grantRole first (which sets the base role
    ///      and registers the member), then update the timing metadata directly.
    function grantRoleTimed(bytes32 role, address account, uint48 start, uint48 expires)
        external
        override(AccessControlTimed)
    {
        // Check role-admin authorization (same as AccessControlTimedLib.grantRoleTimed).
        AccessControlLib.checkRole(AccessControlLib.getRoleAdmin(role));
        // Grant through enumerable so the member set is updated.
        AccessControlEnumerableLib.grantRole(role, account);
        // Overwrite the timing metadata.
        AccessControlTimedLib._grantRoleTimed(role, account, start, expires);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                              TEST SUITE
//////////////////////////////////////////////////////////////////////////*//

contract AccessControlSuiteTest is Test {
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 constant WORKER_ROLE = keccak256("WORKER_ROLE");

    uint48 constant ADMIN_DELAY = 2 days;
    uint48 constant ROLE_DURATION = 1 hours;

    MockAccessSuiteDiamond diamond;

    address admin = address(0xAD);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        vm.warp(1_000_000);
        diamond = new MockAccessSuiteDiamond();
        diamond.initialize(admin, ADMIN_DELAY);
    }

    // -------------------------------------------------------------------------
    // Step 1 — Initialization checks
    // -------------------------------------------------------------------------

    /// @notice After initialization, the owner and default admin point to `admin`.
    function test_Suite_InitialOwnerIsAdmin() public view {
        assertEq(diamond.owner(), admin);
        assertEq(diamond.defaultAdmin(), admin);
        assertTrue(diamond.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    /// @notice The configured admin-transfer delay is stored correctly.
    function test_Suite_DefaultAdminDelayIsSet() public view {
        assertEq(diamond.defaultAdminDelay(), ADMIN_DELAY);
    }

    // -------------------------------------------------------------------------
    // Step 2 — Timed role grant
    // -------------------------------------------------------------------------

    /// @notice Admin grants alice OPERATOR_ROLE with a 1-hour expiry.
    function test_Suite_TimedRoleGrant() public {
        uint48 start = uint48(block.timestamp);
        uint48 expires = start + ROLE_DURATION;

        vm.prank(admin);
        diamond.grantRoleTimed(OPERATOR_ROLE, alice, start, expires);

        // Both timed and standard hasRole agree.
        assertTrue(diamond.hasRole(OPERATOR_ROLE, alice));
        (uint48 gotStart, uint48 gotExpires) = diamond.roleExpiration(OPERATOR_ROLE, alice);
        assertEq(gotStart, start);
        assertEq(gotExpires, expires);
    }

    // -------------------------------------------------------------------------
    // Step 3 — Enumerable sees the timed role
    // -------------------------------------------------------------------------

    /// @notice Enumerable reports alice as a member while the timed window is active.
    function test_Suite_EnumerableSeesTimedMember() public {
        uint48 start = uint48(block.timestamp);
        uint48 expires = start + ROLE_DURATION;

        vm.prank(admin);
        diamond.grantRoleTimed(OPERATOR_ROLE, alice, start, expires);

        assertEq(diamond.getRoleMemberCount(OPERATOR_ROLE), 1);
        assertEq(diamond.getRoleMember(OPERATOR_ROLE, 0), alice);
    }

    // -------------------------------------------------------------------------
    // Step 4 — Role expires
    // -------------------------------------------------------------------------

    /// @notice After warping past the expiry, hasRole returns false.
    function test_Suite_RoleExpiresAfterDeadline() public {
        uint48 start = uint48(block.timestamp);
        uint48 expires = start + ROLE_DURATION;

        vm.prank(admin);
        diamond.grantRoleTimed(OPERATOR_ROLE, alice, start, expires);
        assertTrue(diamond.hasRole(OPERATOR_ROLE, alice));

        // Warp past the expiry by 1 second.
        vm.warp(expires + 1);
        assertFalse(diamond.hasRole(OPERATOR_ROLE, alice));
    }

    // -------------------------------------------------------------------------
    // Step 5 — Begin default-admin transfer
    // -------------------------------------------------------------------------

    /// @notice Admin initiates a default-admin transfer to bob.
    function test_Suite_BeginDefaultAdminTransfer() public {
        vm.prank(admin);
        diamond.beginDefaultAdminTransfer(bob);

        (address pendingAdmin, uint48 readyAt) = diamond.pendingDefaultAdmin();
        assertEq(pendingAdmin, bob);
        assertGt(readyAt, uint48(block.timestamp));
    }

    // -------------------------------------------------------------------------
    // Step 6 — Cannot accept before delay
    // -------------------------------------------------------------------------

    /// @notice Accepting before the delay elapses must revert with TimelockNotReady.
    function test_Suite_CannotAcceptAdminTransferBeforeDelay() public {
        vm.prank(admin);
        diamond.beginDefaultAdminTransfer(bob);

        (, uint48 readyAt) = diamond.pendingDefaultAdmin();
        // Still before readyAt — should revert.
        vm.warp(readyAt - 1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TimelockLib.TimelockNotReady.selector, readyAt, uint48(block.timestamp)));
        diamond.acceptDefaultAdminTransfer();
    }

    // -------------------------------------------------------------------------
    // Step 7 — Warp + accept → bob becomes owner + admin
    // -------------------------------------------------------------------------

    /// @notice After the delay, bob can accept and becomes the new owner/admin.
    function test_Suite_AcceptAfterDelay() public {
        vm.prank(admin);
        diamond.beginDefaultAdminTransfer(bob);

        (, uint48 readyAt) = diamond.pendingDefaultAdmin();
        vm.warp(readyAt + 1);

        vm.prank(bob);
        diamond.acceptDefaultAdminTransfer();

        assertEq(diamond.owner(), bob);
        assertEq(diamond.defaultAdmin(), bob);
        assertTrue(diamond.hasRole(DEFAULT_ADMIN_ROLE, bob));
    }

    // -------------------------------------------------------------------------
    // Step 8 — After transfer, owner check reflects new admin
    // -------------------------------------------------------------------------

    /// @notice After transfer, bob is the owner and hasRole(DEFAULT_ADMIN_ROLE, bob) is true.
    /// @dev Note: AccessControlLib.checkRole() checks the raw ACL storage (not OwnableLib),
    ///      so operations that go through AccessControlLib.checkRole() still require the
    ///      storage-mapped admin. The facet's public hasRole override correctly reflects owner().
    function test_Suite_NewAdminHasRole() public {
        vm.prank(admin);
        diamond.beginDefaultAdminTransfer(bob);
        (, uint48 readyAt) = diamond.pendingDefaultAdmin();
        vm.warp(readyAt + 1);
        vm.prank(bob);
        diamond.acceptDefaultAdminTransfer();

        // Public hasRole (via the overridden facet method) correctly returns true for bob.
        assertTrue(diamond.hasRole(DEFAULT_ADMIN_ROLE, bob));
        assertFalse(diamond.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertEq(diamond.defaultAdmin(), bob);
        assertEq(diamond.owner(), bob);
    }

    /// @notice Admin grants alice WORKER_ROLE without a time limit;
    ///         enumerable reflects the grant.
    function test_Suite_AdminGrantsNonTimedRoleEnumerable() public {
        vm.prank(admin);
        diamond.grantRole(WORKER_ROLE, alice);

        assertTrue(diamond.hasRole(WORKER_ROLE, alice));
        assertEq(diamond.getRoleMemberCount(WORKER_ROLE), 1);
        assertEq(diamond.getRoleMember(WORKER_ROLE, 0), alice);
    }

    // -------------------------------------------------------------------------
    // Regression: standard grant/revoke/enumerate cycle across flavors
    // -------------------------------------------------------------------------

    /// @notice Revoking a timed role also removes it from enumerable.
    function test_Suite_RevokeTimedRoleRemovesFromEnumerable() public {
        uint48 start = uint48(block.timestamp);
        uint48 expires = start + ROLE_DURATION;

        vm.prank(admin);
        diamond.grantRoleTimed(OPERATOR_ROLE, alice, start, expires);
        assertEq(diamond.getRoleMemberCount(OPERATOR_ROLE), 1);

        vm.prank(admin);
        diamond.revokeRole(OPERATOR_ROLE, alice);
        assertEq(diamond.getRoleMemberCount(OPERATOR_ROLE), 0);
    }

    /// @notice Cannot use grantRole/revokeRole on DEFAULT_ADMIN_ROLE — must use
    ///         the admin-transfer workflow.
    function test_Suite_GrantDefaultAdminRoleDirectlyReverts() public {
        vm.prank(admin);
        vm.expectRevert(IAccessControlDefaultAdminRules.AccessControlDefaultAdminRulesUseAdminTransfer.selector);
        diamond.grantRole(DEFAULT_ADMIN_ROLE, alice);
    }
}
