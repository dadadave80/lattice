// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {
    CannotAddFunctionToDiamondThatAlreadyExists,
    CannotRemoveFunctionThatDoesNotExist,
    FacetCut,
    FacetCutAction
} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedDiamondCut} from "@lattice-script/base/governance/DeployGovernedDiamondCut.s.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {UPGRADE_EXECUTOR_ROLE} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";
import {IEmergencyStop} from "@lattice/interfaces/security/IEmergencyStop.sol";
import {EMERGENCY_GUARDIAN_ROLE} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                 FIXTURES
//////////////////////////////////////////////////////////////////////////*//

/// @notice Facet the handler cuts in, replaces and removes. Each probe returns the instance's tag, so the suite can
///         tell which cut a selector routes to.
contract CutProbeFacet {
    uint256 public immutable tag;

    constructor(uint256 tag_) {
        tag = tag_;
    }

    function probe0() external view returns (uint256) {
        return tag;
    }

    function probe1() external view returns (uint256) {
        return tag;
    }

    function probe2() external view returns (uint256) {
        return tag;
    }

    function probe3() external view returns (uint256) {
        return tag;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @title GovernedCutHandler
/// @notice Drives a recipe-built {DeployGovernedDiamondCut} diamond (AccessControl + EmergencyStop +
///         GovernedDiamondCut) through role grants, revocations and renunciations, guardian changes, emergency stop
///         and resume, governed cuts (Add/Replace/Remove of probe selectors), selector freezes, guardian emergency
///         removals, and the diamond itself re-granting the executor role (the external-timelock path).
/// @dev Revert-free under `fail_on_revert`: every call is either valid or arms the exact revert a ghost model of
///      the role table, the stop flag, the frozen set and the installed probes predicts, in the libraries' check
///      order. The root admin (actor 0) is never the target of a DEFAULT_ADMIN_ROLE revocation or renunciation, so a
///      run cannot lock itself out of every admin path; any other holder can lose any role.
contract GovernedCutHandler is Test {
    struct GhostRecord {
        bytes32 cutHash;
        address executor;
        uint48 executedAt;
        uint32 facetCutCount;
    }

    bytes32 public constant DEFAULT_ADMIN = 0x00;
    bytes32 public constant CUSTOM_ROLE = keccak256("GOVERNED_CUT_INVARIANT_CUSTOM_ROLE");
    uint256 public constant PROBES = 4;

    address public immutable diamond;
    address[5] internal _actors;
    bytes32[4] internal _roles;
    bytes4[4] internal _probes;

    mapping(bytes32 role => mapping(address account => bool)) public ghostHasRole;
    bool public ghostStopped;

    /// @dev The facet each probe selector routes to (address(0) when not installed).
    mapping(bytes4 selector => address) public ghostFacet;
    mapping(bytes4 selector => uint256) public ghostTag;
    mapping(bytes4 selector => bool) public ghostFrozen;
    uint256 public ghostFrozenCount;

    GhostRecord[] internal _records;
    uint256 internal _nextTag = 1;

    constructor(address diamond_, address[5] memory actors_) {
        diamond = diamond_;
        _actors = actors_;
        _roles[0] = DEFAULT_ADMIN;
        _roles[1] = EMERGENCY_GUARDIAN_ROLE;
        _roles[2] = UPGRADE_EXECUTOR_ROLE;
        _roles[3] = CUSTOM_ROLE;
        _probes[0] = CutProbeFacet.probe0.selector;
        _probes[1] = CutProbeFacet.probe1.selector;
        _probes[2] = CutProbeFacet.probe2.selector;
        _probes[3] = CutProbeFacet.probe3.selector;
    }

    // ---- Views for the invariants ----

    function actors() external view returns (address[5] memory) {
        return _actors;
    }

    function roles() external view returns (bytes32[4] memory) {
        return _roles;
    }

    function probes() external view returns (bytes4[4] memory) {
        return _probes;
    }

    function recordCount() external view returns (uint256) {
        return _records.length;
    }

    function record(uint256 i) external view returns (GhostRecord memory) {
        return _records[i];
    }

    /// @notice The admin role of `role` as the recipe configures it; no facet in the recipe can change it.
    function adminOf(bytes32 role) public pure returns (bytes32) {
        return role == UPGRADE_EXECUTOR_ROLE ? UPGRADE_EXECUTOR_ROLE : DEFAULT_ADMIN;
    }

    // ---- Setup ----

    /// @notice Setup only: mirrors the roles granted before the campaign starts.
    function seedRole(bytes32 role, address account) external {
        ghostHasRole[role][account] = true;
    }

    // ---- Helpers ----

    function _actor(uint256 seed) internal view returns (address) {
        return _actors[seed % _actors.length];
    }

    function _role(uint256 seed) internal view returns (bytes32) {
        return _roles[seed % _roles.length];
    }

    /// @dev An actor holding `role`, starting the search at `seed`, or the seeded actor when none holds it.
    function _holder(bytes32 role, uint256 seed) internal view returns (address) {
        for (uint256 k; k < _actors.length; ++k) {
            address a = _actors[(seed + k) % _actors.length];
            if (ghostHasRole[role][a]) return a;
        }
        return _actor(seed);
    }

    /// @dev Every second seed acts as a holder of `role`, the rest as any actor, so both paths run.
    function _callerFor(bytes32 role, uint256 seed) internal view returns (address) {
        return seed % 2 == 0 ? _holder(role, seed / 2) : _actor(seed / 2);
    }

    function _single(address facet, FacetCutAction action, bytes4 selector)
        internal
        pure
        returns (FacetCut[] memory c)
    {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = selector;
        c = new FacetCut[](1);
        c[0] = FacetCut({facetAddress: facet, action: action, functionSelectors: sels});
    }

    function _recordCut(FacetCut[] memory cuts, address caller) internal {
        _records.push(
            GhostRecord({
                cutHash: keccak256(abi.encode(cuts, address(0), bytes(""))),
                executor: caller,
                executedAt: uint48(block.timestamp),
                facetCutCount: uint32(cuts.length)
            })
        );
    }

    // ---- Roles ----

    function grantRole(uint256 callerSeed, uint256 roleSeed, uint256 accountSeed) external {
        bytes32 role = _role(roleSeed);
        address caller = _callerFor(adminOf(role), callerSeed);
        address account = _actor(accountSeed);
        bool authorized = ghostHasRole[adminOf(role)][caller];
        if (!authorized) {
            vm.expectRevert(
                abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, adminOf(role))
            );
        }
        vm.prank(caller);
        IAccessControl(diamond).grantRole(role, account);
        if (authorized) ghostHasRole[role][account] = true;
    }

    function revokeRole(uint256 callerSeed, uint256 roleSeed, uint256 accountSeed) external {
        bytes32 role = _role(roleSeed);
        address caller = _callerFor(adminOf(role), callerSeed);
        address account = _actor(accountSeed);
        if (role == DEFAULT_ADMIN && account == _actors[0]) account = _actors[1 + accountSeed % 4];
        bool authorized = ghostHasRole[adminOf(role)][caller];
        if (!authorized) {
            vm.expectRevert(
                abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, adminOf(role))
            );
        }
        vm.prank(caller);
        IAccessControl(diamond).revokeRole(role, account);
        if (authorized) ghostHasRole[role][account] = false;
    }

    /// @dev Renounces for the caller, or (one seed in four) with someone else's confirmation, which is refused.
    function renounceRole(uint256 callerSeed, uint256 roleSeed, uint256 confirmSeed) external {
        bytes32 role = _role(roleSeed);
        address caller = _actor(callerSeed);
        if (role == DEFAULT_ADMIN && caller == _actors[0]) caller = _actors[1 + callerSeed % 4];
        address confirmation = caller;
        if (confirmSeed % 4 == 0) {
            confirmation = _actor(confirmSeed / 4);
            if (confirmation == caller) confirmation = address(0xC0FFEE);
            vm.expectRevert(IAccessControl.AccessControlBadConfirmation.selector);
        }
        vm.prank(caller);
        IAccessControl(diamond).renounceRole(role, confirmation);
        if (confirmation == caller) ghostHasRole[role][caller] = false;
    }

    /// @dev The diamond (the governance executor that holds UPGRADE_EXECUTOR_ROLE and administers it) re-grants the
    ///      executor role to an actor, as a passed proposal would.
    function governanceGrantExecutor(uint256 accountSeed) external {
        address account = _actor(accountSeed);
        vm.prank(diamond);
        IAccessControl(diamond).grantRole(UPGRADE_EXECUTOR_ROLE, account);
        ghostHasRole[UPGRADE_EXECUTOR_ROLE][account] = true;
    }

    // ---- Guardians and the stop flag ----

    function setGuardian(uint256 callerSeed, uint256 accountSeed, bool add) external {
        address caller = _callerFor(DEFAULT_ADMIN, callerSeed);
        address account = _actor(accountSeed);
        bool authorized = ghostHasRole[DEFAULT_ADMIN][caller];
        if (!authorized) {
            vm.expectRevert(
                abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, DEFAULT_ADMIN)
            );
        }
        vm.prank(caller);
        if (add) IEmergencyStop(diamond).addGuardian(account);
        else IEmergencyStop(diamond).removeGuardian(account);
        if (authorized) ghostHasRole[EMERGENCY_GUARDIAN_ROLE][account] = add;
    }

    /// @dev One seed in four acts as a guardian, so the diamond is stopped for a minority of each run.
    function emergencyStop(uint256 callerSeed) external {
        address caller = callerSeed % 4 == 0 ? _holder(EMERGENCY_GUARDIAN_ROLE, callerSeed / 4) : _actor(callerSeed / 4);
        bool ok;
        if (!ghostHasRole[EMERGENCY_GUARDIAN_ROLE][caller]) {
            vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopUnauthorizedGuardian.selector, caller));
        } else if (ghostStopped) {
            vm.expectRevert(IEmergencyStop.EmergencyStopActive.selector);
        } else {
            ok = true;
        }
        vm.prank(caller);
        IEmergencyStop(diamond).emergencyStop("invariant");
        if (ok) ghostStopped = true;
    }

    function emergencyResume(uint256 callerSeed) external {
        address caller = _callerFor(DEFAULT_ADMIN, callerSeed);
        bool ok;
        if (!ghostHasRole[DEFAULT_ADMIN][caller]) {
            vm.expectRevert(
                abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, DEFAULT_ADMIN)
            );
        } else if (!ghostStopped) {
            vm.expectRevert(IEmergencyStop.EmergencyStopNotActive.selector);
        } else {
            ok = true;
        }
        vm.prank(caller);
        IEmergencyStop(diamond).emergencyResume();
        if (ok) ghostStopped = false;
    }

    // ---- Governed cuts ----

    /// @dev A governed cut of one probe selector. The action is the valid one for the probe's ghost state (Add when
    ///      absent, Replace or Remove when installed), or (one seed in eight) the invalid one, which DiamondLib
    ///      refuses. The stop flag, the executor role and the frozen set are checked first, in that order.
    function cut(uint256 callerSeed, uint256 probeSeed, uint256 actionSeed) external {
        address caller = _callerFor(UPGRADE_EXECUTOR_ROLE, callerSeed);
        bytes4 sel = _probes[probeSeed % PROBES];
        bool installed = ghostFacet[sel] != address(0);
        bool invalid = actionSeed % 8 == 0;

        FacetCutAction action;
        address facet;
        uint256 tag = _nextTag++;
        if (installed != invalid) {
            action = actionSeed % 2 == 0 ? FacetCutAction.Replace : FacetCutAction.Remove;
        } else {
            action = FacetCutAction.Add;
        }
        if (action != FacetCutAction.Remove) facet = address(new CutProbeFacet(tag));
        FacetCut[] memory cuts = _single(facet, action, sel);

        bool ok;
        if (ghostStopped) {
            vm.expectRevert(IEmergencyStop.EmergencyStopActive.selector);
        } else if (!ghostHasRole[UPGRADE_EXECUTOR_ROLE][caller]) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector, caller, UPGRADE_EXECUTOR_ROLE
                )
            );
        } else if (action != FacetCutAction.Add && ghostFrozen[sel]) {
            vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, sel));
        } else if (action == FacetCutAction.Add && installed) {
            vm.expectRevert(abi.encodeWithSelector(CannotAddFunctionToDiamondThatAlreadyExists.selector, sel));
        } else if (action != FacetCutAction.Add && !installed) {
            vm.expectRevert(abi.encodeWithSelector(CannotRemoveFunctionThatDoesNotExist.selector, sel));
        } else {
            ok = true;
        }
        vm.prank(caller);
        IGovernedDiamondCut(diamond).diamondCut(cuts, address(0), "");
        if (ok) {
            ghostFacet[sel] = facet;
            ghostTag[sel] = action == FacetCutAction.Remove ? 0 : tag;
            _recordCut(cuts, caller);
        }
    }

    /// @dev Freezes one selector: a probe, or (every second seed) one of eight selectors never cut in, so the probes
    ///      do not all freeze early in a run. Only the executor role may; the stop flag does not gate it.
    function freeze(uint256 callerSeed, uint256 probeSeed) external {
        address caller = _callerFor(UPGRADE_EXECUTOR_ROLE, callerSeed);
        bytes4 sel = probeSeed % 2 == 0
            ? _probes[(probeSeed / 2) % PROBES]
            : bytes4(keccak256(abi.encode("governed-cut-invariant-spare", (probeSeed / 2) % 8)));
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = sel;
        bool authorized = ghostHasRole[UPGRADE_EXECUTOR_ROLE][caller];
        if (!authorized) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector, caller, UPGRADE_EXECUTOR_ROLE
                )
            );
        }
        vm.prank(caller);
        IFrozenSelectors(diamond).freezeSelectors(sels);
        if (authorized && !ghostFrozen[sel]) {
            ghostFrozen[sel] = true;
            ++ghostFrozenCount;
        }
    }

    /// @dev A guardian's emergency removal. Kinds: remove a probe (refused when frozen or absent), remove a protected
    ///      recovery entrypoint (always refused), or a non-Remove action (always refused). Not gated by the stop flag.
    function emergencyRemove(uint256 callerSeed, uint256 probeSeed, uint256 kindSeed) external {
        address caller = _callerFor(EMERGENCY_GUARDIAN_ROLE, callerSeed);
        bytes4 sel = _probes[probeSeed % PROBES];
        uint256 kind = kindSeed % 6;
        FacetCut[] memory cuts;
        bool ok;

        if (!ghostHasRole[EMERGENCY_GUARDIAN_ROLE][caller]) {
            cuts = _single(address(0), FacetCutAction.Remove, sel);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector, caller, EMERGENCY_GUARDIAN_ROLE
                )
            );
        } else if (kind == 0) {
            bytes4[4] memory protected = [
                IGovernedDiamondCut.diamondCut.selector,
                IEmergencyStop.emergencyResume.selector,
                IEmergencyStop.removeGuardian.selector,
                IAccessControl.revokeRole.selector
            ];
            bytes4 p = protected[(kindSeed / 6) % 4];
            cuts = _single(address(0), FacetCutAction.Remove, p);
            vm.expectRevert(abi.encodeWithSelector(IEmergencyCut.EmergencyCutEntrypointProtected.selector, p));
        } else if (kind == 1) {
            cuts = _single(address(this), FacetCutAction.Replace, sel);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IEmergencyCut.EmergencyCutMustBeRemoveOnly.selector, uint8(FacetCutAction.Replace)
                )
            );
        } else {
            cuts = _single(address(0), FacetCutAction.Remove, sel);
            if (ghostFrozen[sel]) {
                vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, sel));
            } else if (ghostFacet[sel] == address(0)) {
                vm.expectRevert(abi.encodeWithSelector(CannotRemoveFunctionThatDoesNotExist.selector, sel));
            } else {
                ok = true;
            }
        }
        vm.prank(caller);
        IEmergencyCut(diamond).emergencyRemoveCut(cuts);
        if (ok) {
            ghostFacet[sel] = address(0);
            ghostTag[sel] = 0;
            _recordCut(cuts, caller);
        }
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                 INVARIANTS
//////////////////////////////////////////////////////////////////////////*//

/// @title GovernedCutDiamondInvariant
/// @notice Stateful properties of the authority surface of a recipe-built {DeployGovernedDiamondCut} diamond (#231):
///         - role membership changes only through an authorised grant or revoke, or the holder's own renunciation,
///           and role admins never change;
///         - cuts land only from an executor while the diamond is not stopped, emergency removals only from a
///           guardian, Remove-only and never on a protected entrypoint;
///         - the upgrade registry is append-only: one record per applied cut, never rewritten;
///         - the frozen set only grows, and a frozen selector's routing never changes again;
///         - selectors route exactly as the ghost cut history says, and the recovery entrypoints never move.
/// forge-config: ci.invariant.runs = 64
contract GovernedCutDiamondInvariant is Test {
    GovernedCutHandler internal handler;
    address internal diamond;

    address internal constant ADMIN = address(0xAD);
    address internal constant EXECUTOR = address(0xE1);
    address internal constant GUARDIAN = address(0x6A);

    bytes4[6] internal _fixedSelectors;
    address[6] internal _fixedFacets;

    function setUp() public {
        vm.warp(1_000_000);
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            new DeployGovernedDiamondCut().buildCuts(ADMIN);
        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond = address(d);

        // The diamond administers UPGRADE_EXECUTOR_ROLE; it hands the role to an executor, as a timelock would.
        vm.prank(diamond);
        IAccessControl(diamond).grantRole(UPGRADE_EXECUTOR_ROLE, EXECUTOR);
        vm.prank(ADMIN);
        IEmergencyStop(diamond).addGuardian(GUARDIAN);

        address[5] memory a = [ADMIN, EXECUTOR, GUARDIAN, address(0xA1), address(0xA2)];
        handler = new GovernedCutHandler(diamond, a);
        handler.seedRole(bytes32(0), ADMIN);
        handler.seedRole(UPGRADE_EXECUTOR_ROLE, EXECUTOR);
        handler.seedRole(EMERGENCY_GUARDIAN_ROLE, GUARDIAN);

        _fixedSelectors = [
            IGovernedDiamondCut.diamondCut.selector,
            IEmergencyStop.emergencyResume.selector,
            IEmergencyStop.removeGuardian.selector,
            IAccessControl.revokeRole.selector,
            IEmergencyCut.emergencyRemoveCut.selector,
            IAccessControl.grantRole.selector
        ];
        for (uint256 i; i < _fixedSelectors.length; ++i) {
            _fixedFacets[i] = DiamondLoupeFacet(diamond).facetAddress(_fixedSelectors[i]);
            assertTrue(_fixedFacets[i] != address(0), "recipe selector missing");
        }

        bytes4[] memory selectors = new bytes4[](12);
        selectors[0] = GovernedCutHandler.grantRole.selector;
        selectors[1] = GovernedCutHandler.revokeRole.selector;
        selectors[2] = GovernedCutHandler.renounceRole.selector;
        selectors[3] = GovernedCutHandler.governanceGrantExecutor.selector;
        selectors[4] = GovernedCutHandler.setGuardian.selector;
        selectors[5] = GovernedCutHandler.emergencyStop.selector;
        selectors[6] = GovernedCutHandler.emergencyResume.selector;
        selectors[7] = GovernedCutHandler.cut.selector;
        // Cuts weighted three times: they are the property under test.
        selectors[8] = GovernedCutHandler.cut.selector;
        selectors[9] = GovernedCutHandler.cut.selector;
        selectors[10] = GovernedCutHandler.freeze.selector;
        selectors[11] = GovernedCutHandler.emergencyRemove.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice Every actor's membership of every role matches the ghost table, role admins are as the recipe set
    ///         them, the diamond keeps the executor role it administers, and `isGuardian` agrees with the role.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_RolesMatchGhost() public view {
        address[5] memory a = handler.actors();
        bytes32[4] memory r = handler.roles();
        for (uint256 i; i < r.length; ++i) {
            assertEq(IAccessControl(diamond).getRoleAdmin(r[i]), handler.adminOf(r[i]), "role admin changed");
            for (uint256 j; j < a.length; ++j) {
                assertEq(IAccessControl(diamond).hasRole(r[i], a[j]), handler.ghostHasRole(r[i], a[j]), "role != ghost");
            }
        }
        for (uint256 j; j < a.length; ++j) {
            assertEq(
                IEmergencyStop(diamond).isGuardian(a[j]),
                handler.ghostHasRole(EMERGENCY_GUARDIAN_ROLE, a[j]),
                "isGuardian != role"
            );
        }
        assertTrue(IAccessControl(diamond).hasRole(UPGRADE_EXECUTOR_ROLE, diamond), "diamond lost the executor role");
        assertTrue(IAccessControl(diamond).hasRole(bytes32(0), ADMIN), "root admin lost");
        assertEq(IEmergencyStop(diamond).isStopped(), handler.ghostStopped(), "stop flag != ghost");
    }

    /// @notice The upgrade registry holds exactly one record per applied cut, each unchanged since it was written.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_CutRegistryAppendOnly() public view {
        uint256 n = handler.recordCount();
        assertEq(IUpgradeRegistry(diamond).cutCount(), n, "cutCount != applied cuts");
        for (uint256 i; i < n; ++i) {
            GovernedCutHandler.GhostRecord memory g = handler.record(i);
            IUpgradeRegistry.CutRecord memory r = IUpgradeRegistry(diamond).getCutRecord(i + 1);
            assertEq(r.cutHash, g.cutHash, "cut record hash rewritten");
            assertEq(r.executor, g.executor, "cut record executor rewritten");
            assertEq(r.executedAt, g.executedAt, "cut record time rewritten");
            assertEq(r.facetCutCount, g.facetCutCount, "cut record size rewritten");
            assertEq(r.init, address(0), "cut record init rewritten");
        }
        assertEq(IUpgradeRegistry(diamond).getCutRecord(n + 1).executor, address(0), "record past cutCount");
    }

    /// @notice Every probe routes to the facet of the last applied cut touching it (or nowhere) and answers with
    ///         that cut's tag; the frozen set is exactly the ghost set; the recovery and cut entrypoints never move.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_RoutingAndFrozenSet() public view {
        bytes4[4] memory p = handler.probes();
        for (uint256 i; i < p.length; ++i) {
            address facet = handler.ghostFacet(p[i]);
            assertEq(DiamondLoupeFacet(diamond).facetAddress(p[i]), facet, "probe routing != ghost");
            if (facet != address(0)) {
                (bool ok, bytes memory ret) = diamond.staticcall(abi.encodeWithSelector(p[i]));
                assertTrue(ok, "installed probe not callable");
                assertEq(abi.decode(ret, (uint256)), handler.ghostTag(p[i]), "probe answers for a stale cut");
            }
            assertEq(IFrozenSelectors(diamond).isSelectorFrozen(p[i]), handler.ghostFrozen(p[i]), "frozen != ghost");
        }
        assertEq(IFrozenSelectors(diamond).frozenSelectors().length, handler.ghostFrozenCount(), "frozen set size");
        for (uint256 i; i < _fixedSelectors.length; ++i) {
            assertEq(DiamondLoupeFacet(diamond).facetAddress(_fixedSelectors[i]), _fixedFacets[i], "entrypoint moved");
        }
    }
}
