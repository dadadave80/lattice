// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title AccessControlSuiteTest
/// @notice Integration test composing AccessControl + AccessControlTimed +
///         AccessControlEnumerable + Ownable in a single mock Diamond.
///
/// Scenario:
///  1. Deploy a Diamond stacking the three AccessControl flavors + Ownable.
///  2. Admin grants a custom role to alice with a 1-hour timed window.
///  3. Verify alice has the role via both the enumerable and timed views.
///  4. Warp past expiry → hasRole returns false.
///  5. Admin grants alice a non-timed role; enumerable picks it up.
///  6. Revoking a timed role also removes it from the enumerable set.
///
/// @dev This suite doubles as the rationale for why the library ships no
///      AccessControlDefaultAdminRules facet: `Ownable` (owner()) and
///      `AccessControl` (DEFAULT_ADMIN_ROLE) compose directly in one Diamond, so the
///      opinionated admin-rules layer is unnecessary. See test_Suite_OwnableAndAccessControlCoexist.

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlEnumerable} from "@lattice/access/AccessControlEnumerable.sol";
import {AccessControlTimed} from "@lattice/access/AccessControlTimed.sol";
import {Ownable} from "@lattice/access/Ownable.sol";
import {AccessControlEnumerableLib} from "@lattice/access/libraries/AccessControlEnumerableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccessControlTimedLib} from "@lattice/access/libraries/AccessControlTimedLib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                           MOCK DIAMOND CONTRACT
//////////////////////////////////////////////////////////////////////////*//

/// @notice Mock Diamond stacking the three AccessControl flavors + Ownable.
/// @dev Multiple inheritance requires explicit overrides for the functions redefined
///      across AccessControl, AccessControlTimed, and AccessControlEnumerable. We delegate
///      to the "most derived" semantics: Enumerable hooks grantRole/revokeRole/renounceRole
///      (member-set maintenance); Timed governs hasRole (time-windowed membership).
contract MockAccessSuiteDiamond is AccessControl, AccessControlTimed, AccessControlEnumerable, Ownable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, AccessControlTimed, AccessControlEnumerable)
        returns (bytes memory)
    {}

    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        OwnableLib.initializeOwner(_admin);
        AccessControlLib.__AccessControl_init(_admin);
        AccessControlTimedLib.__AccessControlTimed_init();
        AccessControlEnumerableLib.__AccessControlEnumerable_init();
        InitializableLib.postInitializer(s);
    }

    // ---- Explicit overrides to resolve diamond-inheritance ambiguity ----

    function hasRole(bytes32 _role, address _account)
        public
        view
        override(AccessControl, AccessControlTimed, AccessControlEnumerable)
        returns (bool)
    {
        // Timed semantics: membership is gated by the active (start, expires) window.
        return AccessControlTimedLib.hasRole(_role, _account);
    }

    function getRoleAdmin(bytes32 _role)
        public
        view
        override(AccessControl, AccessControlTimed, AccessControlEnumerable)
        returns (bytes32)
    {
        return AccessControlLib.getRoleAdmin(_role);
    }

    function grantRole(bytes32 _role, address _account)
        public
        override(AccessControl, AccessControlTimed, AccessControlEnumerable)
    {
        AccessControlEnumerableLib.grantRole(_role, _account);
    }

    function revokeRole(bytes32 _role, address _account)
        public
        override(AccessControl, AccessControlTimed, AccessControlEnumerable)
    {
        AccessControlEnumerableLib.revokeRole(_role, _account);
    }

    function renounceRole(bytes32 _role, address _callerConfirmation)
        public
        override(AccessControl, AccessControlTimed, AccessControlEnumerable)
    {
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

    uint48 constant ROLE_DURATION = 1 hours;

    MockAccessSuiteDiamond diamond;

    address admin = address(0xAD);
    address alice = address(0xA11CE);

    function setUp() public {
        vm.warp(1_000_000);
        diamond = new MockAccessSuiteDiamond();
        diamond.initialize(admin);
    }

    // -------------------------------------------------------------------------
    // Step 1 — Ownable and AccessControl coexist (no DefaultAdminRules needed)
    // -------------------------------------------------------------------------

    /// @notice After init, `admin` is both the Ownable owner and the holder of
    ///         DEFAULT_ADMIN_ROLE. The two mechanisms are independent and compose
    ///         directly — which is why no AccessControlDefaultAdminRules facet is shipped.
    function test_Suite_OwnableAndAccessControlCoexist() public view {
        assertEq(diamond.owner(), admin);
        assertTrue(diamond.hasRole(DEFAULT_ADMIN_ROLE, admin));
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
    // Step 5 — Non-timed grant is enumerable
    // -------------------------------------------------------------------------

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
    // Step 6 — Revoke removes from enumerable
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
}
