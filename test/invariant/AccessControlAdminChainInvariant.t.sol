// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                               MOCK CONTRACT
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal AccessControl mock that exposes setRoleAdmin for handler use.
contract InvAccessControl is AccessControl {
    function initialize(address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        InitializableLib.postInitializer(s);
    }

    /// @notice Exposes the internal setRoleAdmin for testing (unrestricted here).
    function setRoleAdminHelper(bytes32 role, bytes32 adminRole) external {
        AccessControlLib.setRoleAdmin(role, adminRole);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Handler that exercises grantRole, revokeRole, and setRoleAdmin with fuzzed inputs.
contract AccessControlHandler is Test {
    InvAccessControl public ac;

    /// @notice The initial admin, guaranteed to hold DEFAULT_ADMIN_ROLE always.
    address public immutable ADMIN;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    /// @notice Pool of roles actually touched during the run.
    bytes32[] internal _touchedRoles;
    mapping(bytes32 => bool) internal _roleSeen;

    /// @notice Pool of addresses to grant/revoke roles to.
    address[4] internal actors;

    constructor(InvAccessControl ac_, address admin_) {
        ac = ac_;
        ADMIN = admin_;

        actors[0] = address(0xD1);
        actors[1] = address(0xD2);
        actors[2] = address(0xD3);
        actors[3] = address(0xD4);
    }

    function touchedRoles() external view returns (bytes32[] memory) {
        return _touchedRoles;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _touchRole(bytes32 role) internal {
        if (!_roleSeen[role]) {
            _roleSeen[role] = true;
            _touchedRoles.push(role);
        }
    }

    /// @notice Grant a role (called by ADMIN, who always holds DEFAULT_ADMIN_ROLE).
    function grantRole(bytes32 role, uint256 actorSeed) external {
        _touchRole(role);
        address account = _actor(actorSeed);
        // Determine who administers `role`; use ADMIN if admin is DEFAULT_ADMIN_ROLE.
        bytes32 adminRole = ac.getRoleAdmin(role);
        address caller = (adminRole == DEFAULT_ADMIN_ROLE) ? ADMIN : _findHolder(adminRole);
        if (caller == address(0)) return; // no one can grant this role right now
        vm.prank(caller);
        try ac.grantRole(role, account) {} catch {}
    }

    /// @notice Revoke a role — but NEVER revoke DEFAULT_ADMIN_ROLE from ADMIN (that breaks the invariant by design).
    function revokeRole(bytes32 role, uint256 actorSeed) external {
        address account = _actor(actorSeed);
        // Do not revoke DEFAULT_ADMIN_ROLE from our permanent admin.
        if (role == DEFAULT_ADMIN_ROLE && account == ADMIN) return;
        bytes32 adminRole = ac.getRoleAdmin(role);
        address caller = (adminRole == DEFAULT_ADMIN_ROLE) ? ADMIN : _findHolder(adminRole);
        if (caller == address(0)) return;
        vm.prank(caller);
        try ac.revokeRole(role, account) {} catch {}
    }

    /// @notice Change the admin role of a role (only the DEFAULT_ADMIN_ROLE holder can do this via setRoleAdminHelper).
    function setRoleAdmin(bytes32 role, bytes32 newAdminRole) external {
        _touchRole(role);
        _touchRole(newAdminRole);
        // Ensure newAdminRole has a holder before assigning; grant it to ADMIN first.
        if (!ac.hasRole(newAdminRole, ADMIN)) {
            // Use DEFAULT_ADMIN_ROLE to grant newAdminRole to ADMIN.
            vm.prank(ADMIN);
            try ac.grantRole(newAdminRole, ADMIN) {} catch {}
        }
        // setRoleAdminHelper is unrestricted in the mock.
        ac.setRoleAdminHelper(role, newAdminRole);
    }

    /// @notice Find the first actor that holds a given role (returns address(0) if none).
    function _findHolder(bytes32 role) internal view returns (address) {
        if (ac.hasRole(role, ADMIN)) return ADMIN;
        for (uint256 i; i < actors.length; ++i) {
            if (ac.hasRole(role, actors[i])) return actors[i];
        }
        return address(0);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               INVARIANT TEST
//////////////////////////////////////////////////////////////////////////*//

/// @title AccessControlAdminChainInvariant
/// @notice Invariant: for every role that has been touched, its admin role must have
///         at least one current holder — admin chains must never be broken.
contract AccessControlAdminChainInvariant is Test {
    InvAccessControl internal ac;
    AccessControlHandler internal handler;

    address internal admin = address(0xAC_AD);
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    function setUp() public {
        ac = new InvAccessControl();
        ac.initialize(admin);

        handler = new AccessControlHandler(ac, admin);
        targetContract(address(handler));
    }

    /// @notice For every touched role, its getRoleAdmin() must have at least one holder.
    function invariant_AdminChainsValid() public view {
        bytes32[] memory roles = handler.touchedRoles();
        for (uint256 i; i < roles.length; ++i) {
            bytes32 adminRole = ac.getRoleAdmin(roles[i]);
            // DEFAULT_ADMIN_ROLE is guaranteed to have `admin` as a permanent holder.
            if (adminRole == DEFAULT_ADMIN_ROLE) {
                assertTrue(ac.hasRole(DEFAULT_ADMIN_ROLE, admin), "DEFAULT_ADMIN_ROLE has no holder");
                continue;
            }
            // For any other admin role, at least one of the known actors must hold it.
            bool hasHolder = ac.hasRole(adminRole, admin);
            address[4] memory actors;
            actors[0] = address(0xD1);
            actors[1] = address(0xD2);
            actors[2] = address(0xD3);
            actors[3] = address(0xD4);
            for (uint256 j; j < actors.length; ++j) {
                if (ac.hasRole(adminRole, actors[j])) {
                    hasHolder = true;
                    break;
                }
            }
            assertTrue(hasHolder, "admin role has no holder - chain broken");
        }
    }
}
