// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                               MOCK CONTRACT
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal AccessControl mock that exposes the gated setRoleAdmin for handler use.
contract InvAccessControl is AccessControl, Initializable {
    function initialize(address admin_) external initializer {
        AccessControlLib.__AccessControl_init(admin_);
    }

    /// @notice Exposes the gated {AccessControlLib.setRoleAdmin}: the caller must hold `role`'s current admin role.
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external {
        AccessControlLib.setRoleAdmin(role, adminRole);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Handler that drives grantRole, revokeRole, renounceRole and setRoleAdmin from authorised and
///         unauthorised callers over a small role/actor pool, mirroring every authorised change in a ghost model.
/// @dev Every action is revert-free under `fail_on_revert`: an authorised call must succeed (a revert fails the
///      run), and an unauthorised call must revert with the exact access-control error (`vm.expectRevert`), so a
///      missing check also fails the run. The ghost model only changes on authorised calls.
contract AccessControlHandler is Test {
    InvAccessControl public ac;

    /// @notice The initial admin. The handler never authorises it losing DEFAULT_ADMIN_ROLE, which keeps every
    ///         role reachable for the rest of the run.
    address public immutable ADMIN;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;

    address[5] internal _actors;
    bytes32[4] internal _roles;

    /// @notice Ghost model of role membership and role admins.
    mapping(bytes32 role => mapping(address account => bool)) public ghostHasRole;
    mapping(bytes32 role => bytes32 adminRole) public ghostRoleAdmin;

    constructor(InvAccessControl ac_, address admin_) {
        ac = ac_;
        ADMIN = admin_;

        _actors[0] = admin_;
        _actors[1] = address(0xD1);
        _actors[2] = address(0xD2);
        _actors[3] = address(0xD3);
        _actors[4] = address(0xD4);

        _roles[0] = DEFAULT_ADMIN_ROLE;
        _roles[1] = keccak256("ROLE_A");
        _roles[2] = keccak256("ROLE_B");
        _roles[3] = keccak256("ROLE_C");

        ghostHasRole[DEFAULT_ADMIN_ROLE][admin_] = true;
    }

    function actors() external view returns (address[5] memory) {
        return _actors;
    }

    function roles() external view returns (bytes32[4] memory) {
        return _roles;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return _actors[seed % _actors.length];
    }

    function _role(uint256 seed) internal view returns (bytes32) {
        return _roles[seed % _roles.length];
    }

    /// @dev Even seeds pick a current holder of `role` (when one exists) so authorised paths run often; odd seeds
    ///      pick any actor.
    function _callerFor(bytes32 role, uint256 seed) internal view returns (address) {
        if (seed % 2 == 0) {
            for (uint256 i; i < _actors.length; ++i) {
                address candidate = _actors[(seed / 2 + i) % _actors.length];
                if (ghostHasRole[role][candidate]) return candidate;
            }
        }
        return _actor(seed / 2);
    }

    /// @dev Whether the model says `caller` administers `role`; if not, arms the exact expected revert.
    function _authorizedOrExpectRevert(address caller, bytes32 role) internal returns (bool authorized) {
        bytes32 adminRole = ghostRoleAdmin[role];
        authorized = ghostHasRole[adminRole][caller];
        if (!authorized) {
            vm.expectRevert(
                abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, adminRole)
            );
        }
    }

    function grantRole(uint256 callerSeed, uint256 roleSeed, uint256 accountSeed) external {
        bytes32 role = _role(roleSeed);
        address caller = _callerFor(ghostRoleAdmin[role], callerSeed);
        address account = _actor(accountSeed);
        bool authorized = _authorizedOrExpectRevert(caller, role);
        vm.prank(caller);
        ac.grantRole(role, account);
        if (authorized) ghostHasRole[role][account] = true;
    }

    function revokeRole(uint256 callerSeed, uint256 roleSeed, uint256 accountSeed) external {
        bytes32 role = _role(roleSeed);
        address caller = _callerFor(ghostRoleAdmin[role], callerSeed);
        address account = _actor(accountSeed);
        if (role == DEFAULT_ADMIN_ROLE && account == ADMIN && ghostHasRole[ghostRoleAdmin[role]][caller]) return;
        bool authorized = _authorizedOrExpectRevert(caller, role);
        vm.prank(caller);
        ac.revokeRole(role, account);
        if (authorized) ghostHasRole[role][account] = false;
    }

    /// @notice Renounce a role, with a wrong confirmation address on a quarter of the calls.
    function renounceRole(uint256 callerSeed, uint256 roleSeed, uint256 confirmationSeed) external {
        bytes32 role = _role(roleSeed);
        address caller = _callerFor(role, callerSeed);
        if (confirmationSeed % 4 == 0) {
            address wrong = _actors[(callerSeed / 2 + 1) % _actors.length];
            if (wrong == caller) wrong = _actors[(callerSeed / 2 + 2) % _actors.length];
            vm.expectRevert(IAccessControl.AccessControlBadConfirmation.selector);
            vm.prank(caller);
            ac.renounceRole(role, wrong);
            return;
        }
        if (role == DEFAULT_ADMIN_ROLE && caller == ADMIN) return;
        vm.prank(caller);
        ac.renounceRole(role, caller);
        ghostHasRole[role][caller] = false;
    }

    function setRoleAdmin(uint256 callerSeed, uint256 roleSeed, uint256 newAdminSeed) external {
        bytes32 role = _role(roleSeed);
        bytes32 newAdminRole = _role(newAdminSeed);
        address caller = _callerFor(ghostRoleAdmin[role], callerSeed);
        bool authorized = _authorizedOrExpectRevert(caller, role);
        vm.prank(caller);
        ac.setRoleAdmin(role, newAdminRole);
        if (authorized) ghostRoleAdmin[role] = newAdminRole;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               INVARIANT TEST
//////////////////////////////////////////////////////////////////////////*//

/// @title AccessControlRoleModelInvariant
/// @notice Invariant: a role's holders change only through an authorised grantRole, revokeRole or renounceRole,
///         and its admin only through an authorised setRoleAdmin. The on-chain state must always equal the
///         handler's ghost model, which applies only those authorised changes.
contract AccessControlRoleModelInvariant is Test {
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

    /// @notice Every (role, actor) membership equals the ghost model.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_RoleMembershipMatchesModel() public view {
        bytes32[4] memory roles = handler.roles();
        address[5] memory actors = handler.actors();
        for (uint256 i; i < roles.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    ac.hasRole(roles[i], actors[j]),
                    handler.ghostHasRole(roles[i], actors[j]),
                    "role membership diverged from model"
                );
            }
        }
    }

    /// @notice Every role's admin equals the ghost model.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_RoleAdminMatchesModel() public view {
        bytes32[4] memory roles = handler.roles();
        for (uint256 i; i < roles.length; ++i) {
            assertEq(ac.getRoleAdmin(roles[i]), handler.ghostRoleAdmin(roles[i]), "role admin diverged from model");
        }
    }

    /// @notice The initial admin keeps DEFAULT_ADMIN_ROLE: the handler never authorises its removal.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_DefaultAdminRetained() public view {
        assertTrue(ac.hasRole(DEFAULT_ADMIN_ROLE, admin), "DEFAULT_ADMIN_ROLE lost by the initial admin");
    }
}
