// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {GovernedDiamondCutTestBase} from "@lattice-test/base/GovernedDiamondCutTestBase.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernedDiamondCut} from "@lattice/governance/GovernedDiamondCut.sol";
import {
    GOVERNED_DIAMOND_CUT_STORAGE_SLOT,
    UPGRADE_EXECUTOR_ROLE
} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";
import {IEmergencyStop} from "@lattice/interfaces/security/IEmergencyStop.sol";
import {EMERGENCY_GUARDIAN_ROLE} from "@lattice/security/libraries/EmergencyStopLib.sol";

/// @notice A trivial facet whose selector we will Add via a governed cut, to prove the cut applied.
contract DummyFacet {
    function ping() external pure returns (uint256) {
        return 7;
    }
}

/// @notice A no-op init target for exercising the recorded `init` address on a cut.
contract NoopInit {
    function run() external pure {}
}

/// @title GovernedDiamondCutTest
/// @notice Unit tests for the GovernedDiamondCut module. Exercises the facet through a REAL {Diamond}
///         assembled by the ready-to-deploy {DeployGovernedDiamondCut} script (see
///         {GovernedDiamondCutTestBase}) — every call below routes through the diamond's `delegatecall`
///         dispatch, not a flattened inheritance mock. Roles are enforced by the cut-in `AccessControl`, the
///         panic button by `EmergencyStop`; applied cuts are verified via `DiamondLoupeFacet.facetAddress`
///         and ERC-165 advertisement via `ERC165Facet.supportsInterface`.
contract GovernedDiamondCutTest is GovernedDiamondCutTestBase {
    DummyFacet internal dummy;
    address internal admin = address(0xA1);
    address internal stranger = address(0xBEEF);

    function setUp() public {
        diamond = _deployGovernedDiamondCut(admin);
        dummy = new DummyFacet();
    }

    function _addPingCut() internal view returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DummyFacet.ping.selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Add, functionSelectors: sels});
    }

    /// @notice The interface exposes exactly one function (`diamondCut`), so its interfaceId
    ///         equals that function's selector — which is the canonical EIP-2535 cut selector
    ///         0x1f931c1c, identical to IDiamondCut. This is intentional: GovernedDiamondCut
    ///         replaces the stock DiamondCutFacet at the same selector.
    function test_InterfaceIdIsCutSelector() public pure {
        assertEq(
            type(IGovernedDiamondCut).interfaceId,
            bytes4(0x1f931c1c),
            "GovernedDiamondCut iface id must be the cut selector"
        );
    }

    /// @notice The facet's `diamondCut` selector is the canonical EIP-2535 cut selector, so it
    ///         occupies the same selector slot as diamond-lib's stock `DiamondCutFacet`.
    function test_FacetSelectorIsCutSelector() public pure {
        assertEq(GovernedDiamondCut.diamondCut.selector, bytes4(0x1f931c1c), "facet selector mismatch");
    }

    function _erc7201Slot(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff));
    }

    function test_StorageSlotDerivation() public pure {
        assertEq(
            GOVERNED_DIAMOND_CUT_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.GovernedDiamondCut"),
            "GovernedDiamondCut storage slot mismatch"
        );
    }

    function test_UpgradeExecutorRoleConstant() public pure {
        assertEq(UPGRADE_EXECUTOR_ROLE, keccak256("UPGRADE_EXECUTOR_ROLE"), "role constant mismatch");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //               UPGRADE_EXECUTOR_ROLE ADMIN PINNING (self-administered)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The admin of UPGRADE_EXECUTOR_ROLE is pinned to ITSELF at init (not DEFAULT_ADMIN_ROLE).
    ///         This is the core invariant that prevents a DEFAULT_ADMIN_ROLE holder from minting new
    ///         executors out-of-band and bypassing the Governor + Timelock path.
    function test_UpgradeExecutorRoleIsSelfAdministered() public view {
        assertEq(
            ac.getRoleAdmin(UPGRADE_EXECUTOR_ROLE),
            UPGRADE_EXECUTOR_ROLE,
            "UPGRADE_EXECUTOR_ROLE must administer itself, not DEFAULT_ADMIN_ROLE"
        );
        // Explicitly NOT the zero (DEFAULT_ADMIN_ROLE) value — the vulnerable default.
        assertTrue(ac.getRoleAdmin(UPGRADE_EXECUTOR_ROLE) != DEFAULT_ADMIN_ROLE, "must not default to 0x00");
    }

    /// @notice PROOF-OF-VULNERABILITY (now secured): a DEFAULT_ADMIN_ROLE holder (the live `admin`
    ///         EOA) must NOT be able to grant UPGRADE_EXECUTOR_ROLE to an arbitrary attacker. Before
    ///         the fix the role defaulted to DEFAULT_ADMIN_ROLE admin, so this grant SUCCEEDED and the
    ///         attacker could then `diamondCut` directly — bypassing the entire governance/timelock
    ///         path. With the role self-administered, `admin` lacks the admin role and the grant now
    ///         reverts AccessControlUnauthorizedAccount(admin, UPGRADE_EXECUTOR_ROLE).
    function test_AdminCannotGrantUpgradeExecutorRole() public {
        assertTrue(ac.hasRole(DEFAULT_ADMIN_ROLE, admin), "admin holds DEFAULT_ADMIN_ROLE");
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, UPGRADE_EXECUTOR_ROLE
            )
        );
        ac.grantRole(UPGRADE_EXECUTOR_ROLE, stranger);

        // The attacker never received the role, so it still cannot cut.
        assertFalse(ac.hasRole(UPGRADE_EXECUTOR_ROLE, stranger), "attacker must not hold the role");
    }

    /// @notice Closes the loop on the bypass: even after the admin ATTEMPTS the (now-reverting) grant,
    ///         the attacker still cannot reach `diamondCut`. Demonstrates the governance gate holds.
    function test_AdminGrantBypassFullyBlocked() public {
        FacetCut[] memory cuts = _addPingCut();

        // 1) Admin's attempt to mint a new executor reverts.
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, UPGRADE_EXECUTOR_ROLE
            )
        );
        ac.grantRole(UPGRADE_EXECUTOR_ROLE, stranger);

        // 2) Therefore the would-be executor still cannot cut.
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, UPGRADE_EXECUTOR_ROLE
            )
        );
        cut.diamondCut(cuts, address(0), "");
    }

    /// @notice Governance STILL works: because `address(this)` holds UPGRADE_EXECUTOR_ROLE and the role
    ///         administers itself, a timelock-relayed (self) call CAN grant the role to a new executor.
    ///         This proves the fix does not break the legitimate governance grant path. The prank as
    ///         `address(diamond)` models exactly the timelock relaying a passed proposal back in.
    function test_GovernanceCanStillGrantNewExecutor() public {
        address newExecutor = address(0xE0E0);
        assertFalse(ac.hasRole(UPGRADE_EXECUTOR_ROLE, newExecutor), "not an executor yet");

        // The diamond (holding the now-self-administering role) grants it to a new executor.
        vm.prank(address(diamond));
        ac.grantRole(UPGRADE_EXECUTOR_ROLE, newExecutor);
        assertTrue(ac.hasRole(UPGRADE_EXECUTOR_ROLE, newExecutor), "governance must be able to add an executor");

        // And that newly-anointed executor can now actually cut.
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(newExecutor);
        cut.diamondCut(cuts, address(0), "");
        assertEq(loupe.facetAddress(DummyFacet.ping.selector), address(dummy), "new executor's cut must apply");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            GUARDED CUT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Role is granted to the diamond itself, never to an EOA.
    function test_RoleHeldByDiamondNotAdmin() public view {
        assertTrue(ac.hasRole(UPGRADE_EXECUTOR_ROLE, address(diamond)));
        assertFalse(ac.hasRole(UPGRADE_EXECUTOR_ROLE, admin));
    }

    /// @notice A stranger (no role) calling diamondCut reverts with the unauthorized role error.
    function test_UnauthorizedCallerReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, UPGRADE_EXECUTOR_ROLE
            )
        );
        cut.diamondCut(cuts, address(0), "");
    }

    /// @notice Even the admin (DEFAULT_ADMIN_ROLE) cannot cut — the role lives only on address(this).
    function test_AdminCannotCut() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, UPGRADE_EXECUTOR_ROLE
            )
        );
        cut.diamondCut(cuts, address(0), "");
    }

    /// @notice The authorized caller (the diamond itself) applies a real cut: ping selector is bound.
    function test_AuthorizedSelfCallAppliesCut() public {
        FacetCut[] memory cuts = _addPingCut();
        // Impersonate the diamond calling its own diamondCut (this is exactly what the timelock relay
        // achieves in production: msg.sender == address(this)).
        vm.prank(address(diamond));
        cut.diamondCut(cuts, address(0), "");
        assertEq(loupe.facetAddress(DummyFacet.ping.selector), address(dummy), "ping selector not bound");
        // ping() is now callable through the diamond fallback.
        (bool ok, bytes memory ret) = address(diamond).call(abi.encodeWithSelector(DummyFacet.ping.selector));
        assertTrue(ok);
        assertEq(abi.decode(ret, (uint256)), 7);
    }

    /// @notice Emergency stop is the OUTER guard: when stopped, even the authorized caller is blocked,
    ///         and the revert is EmergencyStopActive (not the role error) — proving guard ordering.
    function test_EmergencyStopBlocksAuthorizedCut() public {
        // Make admin a guardian, then trip the stop.
        vm.prank(admin);
        es.addGuardian(admin);
        vm.prank(admin);
        es.emergencyStop("freeze upgrades");

        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(diamond));
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        cut.diamondCut(cuts, address(0), "");
    }

    /// @notice After resume, the authorized cut succeeds again.
    function test_CutSucceedsAfterResume() public {
        vm.prank(admin);
        es.addGuardian(admin);
        vm.prank(admin);
        es.emergencyStop("freeze");
        vm.prank(admin);
        es.emergencyResume();

        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(diamond));
        cut.diamondCut(cuts, address(0), "");
        assertEq(loupe.facetAddress(DummyFacet.ping.selector), address(dummy));
    }

    /// @notice The UpgradeExecuted event fires on a successful cut.
    function test_UpgradeExecutedEventEmitted() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IGovernedDiamondCut.UpgradeExecuted(address(diamond), 1, address(0));
        vm.prank(address(diamond));
        cut.diamondCut(cuts, address(0), "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          UPGRADE REGISTRY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Adds a `replace` cut that re-points the ping selector to a second facet, so we can
    ///         apply a *second* distinct cut (Add then Replace) and assert monotonic versioning.
    function _replacePingCut(address _facet) internal pure returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DummyFacet.ping.selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: _facet, action: FacetCutAction.Replace, functionSelectors: sels});
    }

    /// @notice Before any cut, the registry is empty: cutCount() == 0 and version 1 is unwritten.
    function test_RegistryEmptyBeforeAnyCut() public view {
        assertEq(cut.cutCount(), 0, "cutCount must start at 0");
        IUpgradeRegistry.CutRecord memory rec = cut.getCutRecord(1);
        assertEq(rec.cutHash, bytes32(0));
        assertEq(rec.executor, address(0));
        assertEq(rec.executedAt, 0);
        assertEq(rec.facetCutCount, 0);
        assertEq(rec.init, address(0));
    }

    /// @notice An authorized cut records version 1 with the exact cutHash / executor / timestamp /
    ///         facetCutCount / init. cutHash == keccak256(abi.encode(cuts, init, calldata)).
    function test_RegistryRecordsVersionOne() public {
        vm.warp(123_456);
        FacetCut[] memory cuts = _addPingCut();
        bytes memory cd = bytes("");
        bytes32 expectedHash = keccak256(abi.encode(cuts, address(0), cd));

        vm.prank(address(diamond));
        cut.diamondCut(cuts, address(0), cd);

        assertEq(cut.cutCount(), 1, "cutCount must be 1 after first cut");
        IUpgradeRegistry.CutRecord memory rec = cut.getCutRecord(1);
        assertEq(rec.cutHash, expectedHash, "cutHash mismatch");
        assertEq(rec.executor, address(diamond), "executor must be the caller");
        assertEq(rec.executedAt, uint48(123_456), "executedAt must be block.timestamp");
        assertEq(rec.facetCutCount, uint32(1), "facetCutCount must equal cuts.length");
        assertEq(rec.init, address(0), "init must be recorded");
    }

    /// @notice The init address (non-zero) is captured in the record.
    function test_RegistryRecordsInitAddress() public {
        // Init that adds ping AND delegatecalls a self-call doing nothing harmful: use the diamond
        // itself as init with empty calldata is rejected by diamond-lib (non-empty calldata required
        // for non-zero init), so use a no-op init contract.
        NoopInit noop = new NoopInit();
        FacetCut[] memory cuts = _addPingCut();
        bytes memory cd = abi.encodeWithSelector(NoopInit.run.selector);

        vm.prank(address(diamond));
        cut.diamondCut(cuts, address(noop), cd);

        IUpgradeRegistry.CutRecord memory rec = cut.getCutRecord(1);
        assertEq(rec.init, address(noop), "init address must be recorded");
        assertEq(rec.cutHash, keccak256(abi.encode(cuts, address(noop), cd)), "cutHash must bind init+calldata");
    }

    /// @notice A second cut records version 2 (monotonic), distinct from version 1, and both records
    ///         persist independently.
    function test_RegistryMonotonicSecondVersion() public {
        FacetCut[] memory addCut = _addPingCut();
        vm.prank(address(diamond));
        cut.diamondCut(addCut, address(0), "");

        // Second cut: replace ping with a fresh facet.
        DummyFacet dummy2 = new DummyFacet();
        FacetCut[] memory replaceCut = _replacePingCut(address(dummy2));
        bytes32 expectedHash2 = keccak256(abi.encode(replaceCut, address(0), bytes("")));
        vm.prank(address(diamond));
        cut.diamondCut(replaceCut, address(0), "");

        assertEq(cut.cutCount(), 2, "cutCount must be 2 after second cut");

        IUpgradeRegistry.CutRecord memory rec1 = cut.getCutRecord(1);
        IUpgradeRegistry.CutRecord memory rec2 = cut.getCutRecord(2);
        assertEq(rec1.cutHash, keccak256(abi.encode(addCut, address(0), bytes(""))), "v1 hash preserved");
        assertEq(rec2.cutHash, expectedHash2, "v2 hash mismatch");
        assertTrue(rec1.cutHash != rec2.cutHash, "the two versions must differ");
        assertEq(rec2.facetCutCount, uint32(1));
    }

    /// @notice The CutRecorded event fires with (version, cutHash, executor) on a successful cut.
    function test_RegistryCutRecordedEventEmitted() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 expectedHash = keccak256(abi.encode(cuts, address(0), bytes("")));
        // version indexed, executor indexed; cutHash is in data.
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IUpgradeRegistry.CutRecorded(1, expectedHash, address(diamond));
        vm.prank(address(diamond));
        cut.diamondCut(cuts, address(0), "");
    }

    /// @notice A blocked cut (emergency-stopped) records NOTHING — no phantom version, cutCount stays 0.
    function test_RegistryBlockedCutRecordsNothing() public {
        vm.prank(admin);
        es.addGuardian(admin);
        vm.prank(admin);
        es.emergencyStop("freeze");

        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(diamond));
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        cut.diamondCut(cuts, address(0), "");

        assertEq(cut.cutCount(), 0, "blocked cut must not bump the version counter");
        IUpgradeRegistry.CutRecord memory rec = cut.getCutRecord(1);
        assertEq(rec.executor, address(0), "blocked cut must leave version 1 unwritten");
        assertEq(rec.cutHash, bytes32(0));
    }

    /// @notice An unauthorized cut (no role) records NOTHING — no phantom version.
    function test_RegistryUnauthorizedCutRecordsNothing() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, UPGRADE_EXECUTOR_ROLE
            )
        );
        cut.diamondCut(cuts, address(0), "");

        assertEq(cut.cutCount(), 0, "unauthorized cut must not record a version");
        assertEq(cut.getCutRecord(1).executor, address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          FROZEN SELECTORS
    //////////////////////////////////////////////////////////////////////////*//

    bytes4 internal constant PING_SEL = DummyFacet.ping.selector;
    bytes4 internal constant OTHER_SEL = bytes4(0xDEADBEEF);

    /// @dev A remove cut: facetAddress MUST be address(0) per EIP-2535 remove semantics.
    function _removeCut(bytes4 _sel) internal pure returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = _sel;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(0), action: FacetCutAction.Remove, functionSelectors: sels});
    }

    /// @dev A replace cut targeting `_sel` (re-points it at `dummy`).
    function _replaceCut(bytes4 _sel) internal view returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = _sel;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Replace, functionSelectors: sels});
    }

    function _freeze(bytes4 _sel) internal {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = _sel;
        vm.prank(address(diamond));
        cut.freezeSelectors(sels);
    }

    /// @notice Freezing reflects in isSelectorFrozen / frozenSelectors and is idempotent.
    function test_FreezeReflectsInViews() public {
        assertFalse(cut.isSelectorFrozen(PING_SEL), "not frozen initially");
        assertEq(cut.frozenSelectors().length, 0, "set empty initially");

        _freeze(PING_SEL);

        assertTrue(cut.isSelectorFrozen(PING_SEL), "must be frozen after freeze");
        bytes4[] memory frozen = cut.frozenSelectors();
        assertEq(frozen.length, 1, "one frozen selector");
        assertEq(frozen[0], PING_SEL, "frozen selector recorded");

        // Re-freezing the same selector is an idempotent no-op (no duplicate entry).
        _freeze(PING_SEL);
        assertEq(cut.frozenSelectors().length, 1, "no duplicate on re-freeze");
    }

    /// @notice freezeSelectors is governance-gated: a stranger without the role reverts.
    function test_FreezeSelectorsGovernanceGated() public {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = PING_SEL;
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, UPGRADE_EXECUTOR_ROLE
            )
        );
        cut.freezeSelectors(sels);

        // Even the admin cannot freeze (role lives only on the diamond identity).
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, UPGRADE_EXECUTOR_ROLE
            )
        );
        cut.freezeSelectors(sels);
    }

    /// @notice freezeSelectors emits SelectorsFrozen with the caller + argument array.
    function test_FreezeSelectorsEmitsEvent() public {
        bytes4[] memory sels = new bytes4[](2);
        sels[0] = PING_SEL;
        sels[1] = OTHER_SEL;
        vm.expectEmit(true, false, false, true, address(diamond));
        emit IFrozenSelectors.SelectorsFrozen(address(diamond), sels);
        vm.prank(address(diamond));
        cut.freezeSelectors(sels);
        assertTrue(cut.isSelectorFrozen(PING_SEL));
        assertTrue(cut.isSelectorFrozen(OTHER_SEL));
    }

    /// @notice A governed cut that REMOVES a frozen selector reverts FrozenSelectorProtected,
    ///         BEFORE diamond-lib runs (so the selector need not even be bound).
    function test_FrozenSelectorBlocksRemove() public {
        _freeze(PING_SEL);
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        vm.prank(address(diamond));
        vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, PING_SEL));
        cut.diamondCut(cuts, address(0), "");
    }

    /// @notice A governed cut that REPLACES a frozen selector reverts FrozenSelectorProtected.
    function test_FrozenSelectorBlocksReplace() public {
        _freeze(PING_SEL);
        FacetCut[] memory cuts = _replaceCut(PING_SEL);
        vm.prank(address(diamond));
        vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, PING_SEL));
        cut.diamondCut(cuts, address(0), "");
    }

    /// @notice The frozen guard fires even when the frozen selector is one entry in a multi-cut batch.
    function test_FrozenSelectorBlocksReplaceWithinBatch() public {
        _freeze(OTHER_SEL);
        // First cut Adds ping (fine), second cut Replaces the frozen OTHER_SEL (must revert).
        FacetCut[] memory cuts = new FacetCut[](2);
        cuts[0] = _addPingCut()[0];
        cuts[1] = _replaceCut(OTHER_SEL)[0];
        vm.prank(address(diamond));
        vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, OTHER_SEL));
        cut.diamondCut(cuts, address(0), "");
        // The whole cut reverted: ping was NOT added.
        assertEq(loupe.facetAddress(PING_SEL), address(0), "reverted cut applies nothing");
    }

    /// @notice ADD of a frozen selector is unaffected: only Replace/Remove are protected.
    function test_FrozenSelectorDoesNotBlockAdd() public {
        _freeze(PING_SEL);
        // Adding the (frozen) ping selector still works — Add is not a protected action.
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(diamond));
        cut.diamondCut(cuts, address(0), "");
        assertEq(loupe.facetAddress(PING_SEL), address(dummy), "Add of a frozen selector must succeed");
    }

    /// @notice An Add of an UNRELATED selector still works while another selector is frozen.
    function test_UnrelatedAddWorksWhileFrozen() public {
        _freeze(OTHER_SEL);
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(diamond));
        cut.diamondCut(cuts, address(0), "");
        assertEq(loupe.facetAddress(PING_SEL), address(dummy), "unrelated Add must succeed while frozen");
    }

    /// @notice A non-frozen Remove proceeds (and reaches diamond-lib): removing a bound, non-frozen
    ///         selector succeeds and unbinds it.
    function test_NonFrozenRemoveWorks() public {
        // Bind ping first.
        FacetCut[] memory addCut = _addPingCut();
        vm.prank(address(diamond));
        cut.diamondCut(addCut, address(0), "");
        assertEq(loupe.facetAddress(PING_SEL), address(dummy), "ping bound");

        // Freeze an unrelated selector, then remove the (non-frozen) ping — must succeed.
        _freeze(OTHER_SEL);
        FacetCut[] memory removeCut = _removeCut(PING_SEL);
        vm.prank(address(diamond));
        cut.diamondCut(removeCut, address(0), "");
        assertEq(loupe.facetAddress(PING_SEL), address(0), "non-frozen remove must unbind selector");
    }

    /// @notice previewCut returns ok=false + the offending selector for a frozen-touching Replace.
    function test_PreviewCutDetectsFrozenReplace() public {
        _freeze(PING_SEL);
        FacetCut[] memory cuts = _replaceCut(PING_SEL);
        (bool ok, bytes4 offending) = cut.previewCut(cuts);
        assertFalse(ok, "preview must flag a frozen Replace");
        assertEq(offending, PING_SEL, "preview must return the offending selector");
    }

    /// @notice previewCut returns ok=false + the offending selector for a frozen-touching Remove.
    function test_PreviewCutDetectsFrozenRemove() public {
        _freeze(PING_SEL);
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        (bool ok, bytes4 offending) = cut.previewCut(cuts);
        assertFalse(ok);
        assertEq(offending, PING_SEL);
    }

    /// @notice previewCut returns ok=true (zero offending) for a clean cut (Add, or non-frozen).
    function test_PreviewCutCleanReturnsOk() public {
        _freeze(OTHER_SEL);
        // An Add of the frozen selector is still ok (Add unaffected).
        (bool okAdd, bytes4 offAdd) = cut.previewCut(_addPingCut());
        assertTrue(okAdd, "Add must preview ok");
        assertEq(offAdd, bytes4(0), "no offending selector for ok preview");

        // A Remove of a NON-frozen selector is ok.
        (bool okRm, bytes4 offRm) = cut.previewCut(_removeCut(PING_SEL));
        assertTrue(okRm, "non-frozen Remove must preview ok");
        assertEq(offRm, bytes4(0));
    }

    /// @notice previewCut is a pure read: it does NOT mutate the frozen set or apply the cut.
    function test_PreviewCutDoesNotMutate() public {
        _freeze(PING_SEL);
        cut.previewCut(_replaceCut(PING_SEL));
        // State unchanged: still exactly one frozen selector, ping still unbound.
        assertEq(cut.frozenSelectors().length, 1, "preview must not mutate frozen set");
        assertEq(loupe.facetAddress(PING_SEL), address(0), "preview must not apply the cut");
    }

    /// @notice verifyInterfaceRegistered is true for a registered interface and false otherwise.
    function test_VerifyInterfaceRegistered() public view {
        // IDiamondCut (0x1f931c1c) is registered by DiamondLib.registerInterface() in init.
        assertTrue(cut.verifyInterfaceRegistered(bytes4(0x1f931c1c)), "IDiamondCut must be advertised");
        // IDiamondLoupe (0x48e2b093) is also registered.
        assertTrue(cut.verifyInterfaceRegistered(bytes4(0x48e2b093)), "IDiamondLoupe must be advertised");
        // An arbitrary unregistered id is not advertised.
        assertFalse(cut.verifyInterfaceRegistered(bytes4(0x12345678)), "unknown interface must be false");
        // Mirrors supportsInterface exactly.
        assertEq(
            cut.verifyInterfaceRegistered(bytes4(0x1f931c1c)),
            erc165.supportsInterface(bytes4(0x1f931c1c)),
            "must mirror supportsInterface"
        );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       EMERGENCY REMOVAL-ONLY CUT
    //////////////////////////////////////////////////////////////////////////*//

    address internal guardian = address(0x6044D1A11);

    /// @dev Makes `guardian` an EMERGENCY_GUARDIAN_ROLE holder (the same role the emergency-stop
    ///      panic button uses). Granted by the admin via EmergencyStop's addGuardian.
    function _makeGuardian(address _who) internal {
        vm.prank(admin);
        es.addGuardian(_who);
    }

    /// @dev Binds the ping selector via a normal governed cut so an emergency removal has something
    ///      live to rip out (and routing can be proven to stop).
    function _bindPing() internal {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(diamond));
        cut.diamondCut(cuts, address(0), "");
    }

    /// @dev An Add cut (forbidden on the emergency path).
    function _addCut(bytes4 _sel) internal view returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = _sel;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Add, functionSelectors: sels});
    }

    /// @notice The emergency guardian role constant in the lib equals keccak256("EMERGENCY_GUARDIAN_ROLE")
    ///         and is the SAME role the EmergencyStop panic button uses.
    function test_EmergencyGuardianRoleConstant() public pure {
        assertEq(EMERGENCY_GUARDIAN_ROLE, keccak256("EMERGENCY_GUARDIAN_ROLE"), "guardian role constant mismatch");
    }

    /// @notice ZERO-DELAY REMOVE: a guardian fires emergencyRemoveCut and the live selector instantly
    ///         stops routing (unbound), with no governance round and no timelock delay.
    function test_EmergencyRemove_ZeroDelayUnbindsLiveSelector() public {
        _bindPing();
        assertEq(loupe.facetAddress(PING_SEL), address(dummy), "ping must be live before emergency removal");
        // ping() routes before the emergency cut.
        (bool okBefore,) = address(diamond).call(abi.encodeWithSelector(DummyFacet.ping.selector));
        assertTrue(okBefore, "ping must route before emergency removal");

        _makeGuardian(guardian);
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        vm.prank(guardian);
        cut.emergencyRemoveCut(cuts);

        assertEq(loupe.facetAddress(PING_SEL), address(0), "ping must be unbound after emergency removal");
        // ping() no longer routes (no facet for the selector).
        (bool okAfter,) = address(diamond).call(abi.encodeWithSelector(DummyFacet.ping.selector));
        assertFalse(okAfter, "ping must stop routing after emergency removal");
    }

    /// @notice AUTH GATE (stranger): a non-guardian reverts AccessControlUnauthorizedAccount for the
    ///         guardian role.
    function test_EmergencyRemove_StrangerReverts() public {
        _bindPing();
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, EMERGENCY_GUARDIAN_ROLE
            )
        );
        cut.emergencyRemoveCut(cuts);
    }

    /// @notice AUTH GATE (wrong role): a holder of ONLY UPGRADE_EXECUTOR_ROLE (the diamond identity)
    ///         is NOT a guardian, so it cannot fire the emergency removal — proving the emergency path
    ///         is a distinct, guardian-only authority, not the governance authority.
    function test_EmergencyRemove_UpgradeExecutorWithoutGuardianReverts() public {
        _bindPing();
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        // address(diamond) holds UPGRADE_EXECUTOR_ROLE but was never granted EMERGENCY_GUARDIAN_ROLE.
        assertTrue(ac.hasRole(UPGRADE_EXECUTOR_ROLE, address(diamond)), "diamond holds executor role");
        assertFalse(ac.hasRole(EMERGENCY_GUARDIAN_ROLE, address(diamond)), "diamond is not a guardian");
        vm.prank(address(diamond));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(diamond), EMERGENCY_GUARDIAN_ROLE
            )
        );
        cut.emergencyRemoveCut(cuts);
    }

    /// @notice REMOVE-ONLY rejects Add: an emergency cut containing an Add reverts
    ///         EmergencyCutMustBeRemoveOnly(0) — a guardian can never add code.
    function test_EmergencyRemove_RejectsAdd() public {
        _makeGuardian(guardian);
        FacetCut[] memory cuts = _addCut(PING_SEL);
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(IEmergencyCut.EmergencyCutMustBeRemoveOnly.selector, uint8(FacetCutAction.Add))
        );
        cut.emergencyRemoveCut(cuts);
    }

    /// @notice REMOVE-ONLY rejects Replace: an emergency cut containing a Replace reverts
    ///         EmergencyCutMustBeRemoveOnly(1) — a guardian can never replace code.
    function test_EmergencyRemove_RejectsReplace() public {
        _makeGuardian(guardian);
        FacetCut[] memory cuts = _replaceCut(PING_SEL);
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(IEmergencyCut.EmergencyCutMustBeRemoveOnly.selector, uint8(FacetCutAction.Replace))
        );
        cut.emergencyRemoveCut(cuts);
    }

    /// @notice REMOVE-ONLY rejects a mixed batch: a Remove followed by an Add still reverts on the Add,
    ///         and nothing is applied (the prior Remove does not take effect).
    function test_EmergencyRemove_RejectsMixedBatch() public {
        _bindPing();
        _makeGuardian(guardian);
        FacetCut[] memory cuts = new FacetCut[](2);
        cuts[0] = _removeCut(PING_SEL)[0]; // valid Remove
        cuts[1] = _addCut(OTHER_SEL)[0]; // invalid Add -> whole call must revert
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(IEmergencyCut.EmergencyCutMustBeRemoveOnly.selector, uint8(FacetCutAction.Add))
        );
        cut.emergencyRemoveCut(cuts);
        // Reverted atomically: ping is still bound (the valid Remove never committed).
        assertEq(loupe.facetAddress(PING_SEL), address(dummy), "mixed-batch revert must apply nothing");
    }

    /// @notice FROZEN PROTECTED: a guardian cannot rip out a frozen (load-bearing) selector — the
    ///         emergency removal reverts FrozenSelectorProtected just like a governed Replace/Remove.
    function test_EmergencyRemove_FrozenSelectorProtected() public {
        _bindPing();
        _freeze(PING_SEL);
        _makeGuardian(guardian);
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, PING_SEL));
        cut.emergencyRemoveCut(cuts);
        // Frozen selector survived: still bound.
        assertEq(loupe.facetAddress(PING_SEL), address(dummy), "frozen selector must survive emergency removal");
    }

    /// @notice WORKS DURING STOP: with EmergencyStop engaged the normal diamondCut reverts
    ///         EmergencyStopActive, but emergencyRemoveCut INTENTIONALLY goes through — it is the panic
    ///         button that must work precisely when upgrades are halted.
    function test_EmergencyRemove_WorksWhileEmergencyStopped() public {
        _bindPing();
        // admin becomes a guardian (so it can both trip the stop AND fire the emergency cut).
        _makeGuardian(admin);
        vm.prank(admin);
        es.emergencyStop("incident: facet compromised");
        assertTrue(es.isStopped(), "stop must be engaged");

        // The NORMAL governed cut is blocked while stopped.
        FacetCut[] memory addCut = _addPingCut();
        vm.prank(address(diamond));
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        cut.diamondCut(addCut, address(0), "");

        // The EMERGENCY removal goes through DESPITE the stop.
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        vm.prank(admin);
        cut.emergencyRemoveCut(cuts);
        assertEq(loupe.facetAddress(PING_SEL), address(0), "emergency removal must work during a stop");
    }

    /// @notice RECORDED + EVENT: an emergency removal is recorded in the SAME append-only registry
    ///         (cutCount increments, record fields sane: removal-only so init == address(0), the
    ///         cutHash binds the removal cut) and emits EmergencyCutExecuted(version, guardian, count).
    function test_EmergencyRemove_RecordedAndEmitsEvent() public {
        vm.warp(987_654);
        _bindPing(); // version 1 (the binding governed cut)
        assertEq(cut.cutCount(), 1, "binding cut is version 1");

        _makeGuardian(guardian);
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        bytes32 expectedHash = keccak256(abi.encode(cuts, address(0), bytes("")));

        // EmergencyCutExecuted(version=2, guardian, selectorCount=1) — version & guardian indexed.
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IEmergencyCut.EmergencyCutExecuted(2, guardian, 1);
        vm.prank(guardian);
        cut.emergencyRemoveCut(cuts);

        // Registry bumped to version 2 and the record reflects the emergency removal.
        assertEq(cut.cutCount(), 2, "emergency removal must bump the registry version");
        IUpgradeRegistry.CutRecord memory rec = cut.getCutRecord(2);
        assertEq(rec.cutHash, expectedHash, "emergency cutHash must bind the removal cut");
        assertEq(rec.executor, guardian, "executor must be the guardian");
        assertEq(rec.executedAt, uint48(987_654), "executedAt must be block.timestamp");
        assertEq(rec.facetCutCount, uint32(1), "facetCutCount must equal cuts.length");
        assertEq(rec.init, address(0), "emergency removal records no init (removal-only)");
    }

    /// @notice The emergency registry record also surfaces via CutRecorded (shared registry), so an
    ///         emergency removal appears in cut history exactly like a governed cut.
    function test_EmergencyRemove_AlsoEmitsCutRecorded() public {
        _bindPing();
        _makeGuardian(guardian);
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        bytes32 expectedHash = keccak256(abi.encode(cuts, address(0), bytes("")));
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IUpgradeRegistry.CutRecorded(2, expectedHash, guardian);
        vm.prank(guardian);
        cut.emergencyRemoveCut(cuts);
    }

    /// @notice selectorCount in EmergencyCutExecuted sums selectors across multiple Remove entries.
    function test_EmergencyRemove_SelectorCountAcrossBatch() public {
        // Bind ping, and bind a second selector on a second facet so we can remove two selectors.
        _bindPing();
        DummyFacet dummy2 = new DummyFacet();
        // Bind OTHER_SEL by adding it on dummy2 (a distinct selector mapping to ping's body is fine for
        // routing purposes; we only need it bound so a Remove succeeds in diamond-lib).
        bytes4[] memory sels2 = new bytes4[](1);
        sels2[0] = OTHER_SEL;
        FacetCut[] memory addOther = new FacetCut[](1);
        addOther[0] = FacetCut({facetAddress: address(dummy2), action: FacetCutAction.Add, functionSelectors: sels2});
        vm.prank(address(diamond));
        cut.diamondCut(addOther, address(0), "");

        _makeGuardian(guardian);
        // One emergency cut removing BOTH selectors (two Remove entries -> selectorCount == 2).
        bytes4[] memory rmA = new bytes4[](1);
        rmA[0] = PING_SEL;
        bytes4[] memory rmB = new bytes4[](1);
        rmB[0] = OTHER_SEL;
        FacetCut[] memory cuts = new FacetCut[](2);
        cuts[0] = FacetCut({facetAddress: address(0), action: FacetCutAction.Remove, functionSelectors: rmA});
        cuts[1] = FacetCut({facetAddress: address(0), action: FacetCutAction.Remove, functionSelectors: rmB});

        vm.expectEmit(true, true, false, true, address(diamond));
        emit IEmergencyCut.EmergencyCutExecuted(3, guardian, 2);
        vm.prank(guardian);
        cut.emergencyRemoveCut(cuts);

        assertEq(loupe.facetAddress(PING_SEL), address(0), "ping removed");
        assertEq(loupe.facetAddress(OTHER_SEL), address(0), "other removed");
    }
}
