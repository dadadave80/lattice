// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title MockAccessControlContract
/// @notice Mock contract using AccessControl for testing
contract MockAccessControlContract is AccessControl {
    bytes32 public constant RESTRICTED_ROLE = keccak256("RESTRICTED_ROLE");

    /// @notice Initializes access control with an admin
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        InitializableLib.postInitializer(s);
    }

    /// @notice Example function that requires a role
    /// @dev Demonstrates role-based access control
    function restrictedFunction() external {
        AccessControlLib.checkRole(RESTRICTED_ROLE);
    }

    /// @notice Helper to set role admin from tests
    function setRoleAdminHelper(bytes32 _role, bytes32 _adminRole) external {
        AccessControlLib.setRoleAdmin(_role, _adminRole);
    }

    function supportsInterface(bytes4 _interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

/// @title AccessControlTester
/// @notice Comprehensive tests for AccessControl contract and library
contract AccessControlTester is Test {
    MockAccessControlContract accessControl;

    bytes32 private constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 private constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 private constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 private constant RESTRICTED_ROLE = keccak256("RESTRICTED_ROLE");

    address admin = address(0x1);
    address user = address(0x2);
    address other = address(0x3);

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    function setUp() public {
        accessControl = new MockAccessControlContract();
        accessControl.initialize(admin);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               HASROLE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Admin should have DEFAULT_ADMIN_ROLE after initialization
    function test_AdminHasDefaultAdminRole() public view {
        assertTrue(accessControl.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    /// @notice User should not have DEFAULT_ADMIN_ROLE initially
    function test_UserDoesNotHaveDefaultAdminRoleInitially() public view {
        assertFalse(accessControl.hasRole(DEFAULT_ADMIN_ROLE, user));
    }

    /// @notice Non-admin user should not have custom roles initially
    function test_UserDoesNotHaveCustomRoleInitially() public view {
        assertFalse(accessControl.hasRole(MINTER_ROLE, user));
    }

    /// @notice User should have role after being granted
    function test_UserHasRoleAfterGrant() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);

        assertTrue(accessControl.hasRole(MINTER_ROLE, user));
    }

    /// @notice hasRole should return false after role is revoked
    function test_HasRoleReturnsFalseAfterRevoke() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);
        assertTrue(accessControl.hasRole(MINTER_ROLE, user));

        vm.prank(admin);
        accessControl.revokeRole(MINTER_ROLE, user);
        assertFalse(accessControl.hasRole(MINTER_ROLE, user));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            GETROLEADMIN TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice DEFAULT_ADMIN_ROLE should be its own admin
    function test_DefaultAdminRoleIsOwnAdmin() public view {
        bytes32 adminRole = accessControl.getRoleAdmin(DEFAULT_ADMIN_ROLE);
        assertEq(adminRole, DEFAULT_ADMIN_ROLE);
    }

    /// @notice New role should have DEFAULT_ADMIN_ROLE as admin initially
    function test_NewRoleHasDefaultAdminAsAdmin() public view {
        bytes32 adminRole = accessControl.getRoleAdmin(MINTER_ROLE);
        assertEq(adminRole, DEFAULT_ADMIN_ROLE);
    }

    /// @notice Custom role should have correct admin after setRoleAdmin
    function test_RoleAdminCanBeChanged() public {
        // Verify initial admin is DEFAULT_ADMIN_ROLE
        assertEq(accessControl.getRoleAdmin(MINTER_ROLE), DEFAULT_ADMIN_ROLE);

        // setRoleAdmin operates on shared storage, so we just test via getRoleAdmin
        vm.prank(admin);
        accessControl.setRoleAdminHelper(MINTER_ROLE, ADMIN_ROLE);
        // Now check via a new call to ensure it was set
        bytes32 actualAdmin = accessControl.getRoleAdmin(MINTER_ROLE);
        assertEq(actualAdmin, ADMIN_ROLE);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            GRANTROLE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Only admin can grant roles
    function test_OnlyAdminCanGrantRole() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, DEFAULT_ADMIN_ROLE)
        );
        accessControl.grantRole(MINTER_ROLE, other);
    }

    /// @notice Admin can grant roles
    function test_AdminCanGrantRole() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);

        assertTrue(accessControl.hasRole(MINTER_ROLE, user));
    }

    /// @notice Granting role emits RoleGranted event
    function test_GrantRoleEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit RoleGranted(MINTER_ROLE, user, admin);
        accessControl.grantRole(MINTER_ROLE, user);
    }

    /// @notice Granting same role twice only emits event once
    function test_GrantingSameRoleTwiceEmitsOnce() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);

        vm.prank(admin);
        vm.recordLogs();
        accessControl.grantRole(MINTER_ROLE, user);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify no RoleGranted event was emitted
        bool eventFound = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("RoleGranted(bytes32,address,address)")) {
                eventFound = true;
                break;
            }
        }
        assertFalse(eventFound, "RoleGranted event should not be emitted when role already exists");
    }

    /// @notice User with admin role for a role can grant that role
    function test_RoleAdminCanGrantRole() public {
        // Grant ADMIN_ROLE to user first
        vm.prank(admin);
        accessControl.grantRole(ADMIN_ROLE, user);

        // Set MINTER_ROLE admin to ADMIN_ROLE
        vm.prank(admin);
        accessControl.setRoleAdminHelper(MINTER_ROLE, ADMIN_ROLE);

        // User should be able to grant MINTER_ROLE
        vm.prank(user);
        accessControl.grantRole(MINTER_ROLE, other);

        assertTrue(accessControl.hasRole(MINTER_ROLE, other));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            REVOKEROLE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Only admin can revoke roles
    function test_OnlyAdminCanRevokeRole() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);

        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, DEFAULT_ADMIN_ROLE)
        );
        accessControl.revokeRole(MINTER_ROLE, user);
    }

    /// @notice Admin can revoke roles
    function test_AdminCanRevokeRole() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);

        vm.prank(admin);
        accessControl.revokeRole(MINTER_ROLE, user);

        assertFalse(accessControl.hasRole(MINTER_ROLE, user));
    }

    /// @notice Revoking role emits RoleRevoked event
    function test_RevokeRoleEmitsEvent() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(MINTER_ROLE, user, admin);
        accessControl.revokeRole(MINTER_ROLE, user);
    }

    /// @notice Revoking role from account that doesn't have it doesn't emit event
    function test_RevokingNonExistentRoleDoesNotEmitEvent() public {
        vm.prank(admin);
        vm.recordLogs();
        accessControl.revokeRole(MINTER_ROLE, user);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify no RoleRevoked event was emitted
        bool eventFound = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("RoleRevoked(bytes32,address,address)")) {
                eventFound = true;
                break;
            }
        }
        assertFalse(eventFound, "RoleRevoked event should not be emitted for non-existent role");
    }

    /// @notice Role admin can revoke roles they admin
    function test_RoleAdminCanRevokeRole() public {
        // Grant ADMIN_ROLE to user
        vm.prank(admin);
        accessControl.grantRole(ADMIN_ROLE, user);

        // Set MINTER_ROLE admin to ADMIN_ROLE
        vm.prank(admin);
        accessControl.setRoleAdminHelper(MINTER_ROLE, ADMIN_ROLE);

        // Grant MINTER_ROLE to other
        vm.prank(user);
        accessControl.grantRole(MINTER_ROLE, other);

        // User should be able to revoke MINTER_ROLE
        vm.prank(user);
        accessControl.revokeRole(MINTER_ROLE, other);

        assertFalse(accessControl.hasRole(MINTER_ROLE, other));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            RENOUNCEROLE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Account can renounce its own role
    function test_AccountCanRenounceOwnRole() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);

        vm.prank(user);
        accessControl.renounceRole(MINTER_ROLE, user);

        assertFalse(accessControl.hasRole(MINTER_ROLE, user));
    }

    /// @notice Renouncing role emits RoleRevoked event
    function test_RenounceRoleEmitsEvent() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(MINTER_ROLE, user, user);
        accessControl.renounceRole(MINTER_ROLE, user);
    }

    /// @notice Account cannot renounce role with wrong confirmation
    function test_CannotRenounceWithWrongConfirmation() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);

        vm.prank(user);
        vm.expectRevert(IAccessControl.AccessControlBadConfirmation.selector);
        accessControl.renounceRole(MINTER_ROLE, other);
    }

    /// @notice Account can only renounce if confirmation matches msg.sender
    function test_RenounceRequiresCorrectConfirmation() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);

        // other is calling but user is the confirmation - should fail
        vm.prank(other);
        vm.expectRevert(IAccessControl.AccessControlBadConfirmation.selector);
        accessControl.renounceRole(MINTER_ROLE, user);
    }

    /// @notice Admin can renounce DEFAULT_ADMIN_ROLE with confirmation
    function test_AdminCanRenounceDefaultAdminRole() public {
        vm.prank(admin);
        accessControl.renounceRole(DEFAULT_ADMIN_ROLE, admin);

        assertFalse(accessControl.hasRole(DEFAULT_ADMIN_ROLE, admin));
    }

    /// @notice Renouncing non-existent role doesn't emit event
    function test_RenounceNonExistentRoleDoesNotEmitEvent() public {
        vm.prank(user);
        vm.recordLogs();
        accessControl.renounceRole(MINTER_ROLE, user);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify no RoleRevoked event was emitted
        bool eventFound = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("RoleRevoked(bytes32,address,address)")) {
                eventFound = true;
                break;
            }
        }
        assertFalse(eventFound, "RoleRevoked event should not be emitted for non-existent role");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            ONLYROLE MODIFIER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Function with onlyRole modifier can be called by account with role
    function test_OnlyRoleAllowsAccountWithRole() public {
        vm.prank(admin);
        accessControl.grantRole(RESTRICTED_ROLE, user);

        vm.prank(user);
        // This should not revert
        accessControl.restrictedFunction();
    }

    /// @notice Function with onlyRole modifier reverts for account without role
    function test_OnlyRoleRevertsWithoutRole() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, RESTRICTED_ROLE)
        );
        accessControl.restrictedFunction();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ROLEADMINCHANGED TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice setRoleAdmin emits RoleAdminChanged event
    function test_SetRoleAdminEmitsEvent() public {
        bytes32 previousAdmin = accessControl.getRoleAdmin(MINTER_ROLE);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit RoleAdminChanged(MINTER_ROLE, previousAdmin, ADMIN_ROLE);
        accessControl.setRoleAdminHelper(MINTER_ROLE, ADMIN_ROLE);
    }

    /// @notice Role admin can be changed multiple times
    function test_RoleAdminCanBeChangedMultipleTimes() public {
        vm.prank(admin);
        accessControl.setRoleAdminHelper(MINTER_ROLE, ADMIN_ROLE);
        assertEq(accessControl.getRoleAdmin(MINTER_ROLE), ADMIN_ROLE);

        // Now MINTER_ROLE's admin is ADMIN_ROLE; admin has DEFAULT_ADMIN_ROLE but not ADMIN_ROLE.
        // Grant admin the ADMIN_ROLE so they can change MINTER_ROLE's admin again.
        vm.prank(admin);
        accessControl.grantRole(ADMIN_ROLE, admin);

        vm.prank(admin);
        accessControl.setRoleAdminHelper(MINTER_ROLE, BURNER_ROLE);
        assertEq(accessControl.getRoleAdmin(MINTER_ROLE), BURNER_ROLE);

        // Grant admin the BURNER_ROLE so they can change MINTER_ROLE's admin again.
        vm.prank(admin);
        accessControl.grantRole(BURNER_ROLE, admin);

        vm.prank(admin);
        accessControl.setRoleAdminHelper(MINTER_ROLE, DEFAULT_ADMIN_ROLE);
        assertEq(accessControl.getRoleAdmin(MINTER_ROLE), DEFAULT_ADMIN_ROLE);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            MULTIPLE ROLES TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Account can have multiple roles
    function test_AccountCanHaveMultipleRoles() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);

        vm.prank(admin);
        accessControl.grantRole(BURNER_ROLE, user);

        assertTrue(accessControl.hasRole(MINTER_ROLE, user));
        assertTrue(accessControl.hasRole(BURNER_ROLE, user));
    }

    /// @notice Revoking one role doesn't affect other roles
    function test_RevokingOneRoleDoesNotAffectOthers() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);

        vm.prank(admin);
        accessControl.grantRole(BURNER_ROLE, user);

        vm.prank(admin);
        accessControl.revokeRole(MINTER_ROLE, user);

        assertFalse(accessControl.hasRole(MINTER_ROLE, user));
        assertTrue(accessControl.hasRole(BURNER_ROLE, user));
    }

    /// @notice Multiple accounts can have the same role
    function test_MultipleAccountsCanHaveSameRole() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, user);

        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, other);

        assertTrue(accessControl.hasRole(MINTER_ROLE, user));
        assertTrue(accessControl.hasRole(MINTER_ROLE, other));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              EDGE CASES TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Account with zero address can receive roles
    function test_ZeroAddressCanReceiveRole() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, address(0));

        assertTrue(accessControl.hasRole(MINTER_ROLE, address(0)));
    }

    /// @notice Different role identifiers are independent
    function test_DifferentRolesAreIndependent() public view {
        bytes32 role1 = keccak256("ROLE_1");
        bytes32 role2 = keccak256("ROLE_2");

        assertFalse(accessControl.hasRole(role1, user));
        assertFalse(accessControl.hasRole(role2, user));
    }

    /// @notice Role with all bits set can be used
    function test_MaxRoleCanBeUsed() public {
        bytes32 maxRole = bytes32(type(uint256).max);

        vm.prank(admin);
        accessControl.grantRole(maxRole, user);

        assertTrue(accessControl.hasRole(maxRole, user));
    }

    /// @notice Admin can grant role to themselves
    function test_AdminCanGrantRoleToThemselves() public {
        vm.prank(admin);
        accessControl.grantRole(MINTER_ROLE, admin);

        assertTrue(accessControl.hasRole(MINTER_ROLE, admin));
    }

    /// @notice Multiple rapid grants work correctly
    function test_MultipleRapidGrants() public {
        bytes32 role = keccak256("TEST_ROLE");

        for (uint256 i = 0; i < 10; i++) {
            address testAddr = address(uint160(0x100 + i));
            vm.prank(admin);
            accessControl.grantRole(role, testAddr);
            assertTrue(accessControl.hasRole(role, testAddr));
        }
    }

    /// @notice Complex role hierarchy works correctly
    function test_ComplexRoleHierarchy() public {
        bytes32 superAdminRole = keccak256("SUPER_ADMIN");
        bytes32 managerRole = keccak256("MANAGER");
        bytes32 operatorRole = keccak256("OPERATOR");

        // Set up hierarchy: DEFAULT_ADMIN -> SUPER_ADMIN -> MANAGER -> OPERATOR
        // admin has DEFAULT_ADMIN_ROLE which is the admin of all new roles by default.
        vm.prank(admin);
        accessControl.setRoleAdminHelper(superAdminRole, DEFAULT_ADMIN_ROLE);
        vm.prank(admin);
        accessControl.setRoleAdminHelper(managerRole, superAdminRole);
        // Now managerRole's admin is superAdminRole; user must have superAdminRole to set operatorRole's admin.
        vm.prank(admin);
        accessControl.grantRole(superAdminRole, admin);
        vm.prank(admin);
        accessControl.setRoleAdminHelper(operatorRole, managerRole);

        // Admin grants SUPER_ADMIN to user
        vm.prank(admin);
        accessControl.grantRole(superAdminRole, user);

        // User grants MANAGER to other
        vm.prank(user);
        accessControl.grantRole(managerRole, other);

        // Other grants OPERATOR to a third party
        address third = address(0x4);
        vm.prank(other);
        accessControl.grantRole(operatorRole, third);

        // Verify all roles were granted correctly
        assertTrue(accessControl.hasRole(superAdminRole, user));
        assertTrue(accessControl.hasRole(managerRole, other));
        assertTrue(accessControl.hasRole(operatorRole, third));
    }

    function test_SupportsInterface() public view {
        // AccessControl should support IAccessControl interface
        bytes4 interfaceId = type(IAccessControl).interfaceId;
        assertTrue(accessControl.supportsInterface(interfaceId));
    }
}
