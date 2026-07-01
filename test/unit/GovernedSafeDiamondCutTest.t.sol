// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {GovernedSafeDiamondCutTestBase, MockSafe} from "@lattice-test/base/GovernedSafeDiamondCutTestBase.sol";
import {GovernedSafeDiamondCut} from "@lattice/governance/GovernedSafeDiamondCut.sol";
import {GOVERNED_SAFE_DIAMOND_CUT_STORAGE_SLOT} from "@lattice/governance/libraries/GovernedSafeDiamondCutLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {IGovernedSafeDiamondCut} from "@lattice/interfaces/governance/IGovernedSafeDiamondCut.sol";
import {ISafeAuthority} from "@lattice/interfaces/governance/ISafeAuthority.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";
import {IEmergencyStop} from "@lattice/interfaces/security/IEmergencyStop.sol";
import {EMERGENCY_GUARDIAN_ROLE} from "@lattice/security/libraries/EmergencyStopLib.sol";

/// @notice A trivial facet whose selector we Add via a scheduled cut, to prove the cut applied.
contract DummyFacet {
    function ping() external pure returns (uint256) {
        return 7;
    }
}

/// @title GovernedSafeDiamondCutTest
/// @notice Unit tests for the GovernedSafeDiamondCut (Safe + built-in timelock) module. Exercises the facet
///         through a REAL {Diamond} assembled by the ready-to-deploy {DeployGovernedSafeDiamondCut} script
///         (see {GovernedSafeDiamondCutTestBase}) — every call below routes through the diamond's
///         `delegatecall` dispatch, not a flattened inheritance mock. Applied cuts are verified via
///         `DiamondLoupeFacet.facetAddress`; ERC-165 advertisement via `ERC165Facet.supportsInterface`.
contract GovernedSafeDiamondCutTest is GovernedSafeDiamondCutTestBase {
    MockSafe internal safe;
    DummyFacet internal dummy;
    address internal admin = address(0xA1);
    address internal stranger = address(0xBEEF);
    uint256 internal constant MIN_THRESHOLD = 2;
    uint256 internal constant MIN_DELAY = 2 days;
    bytes32 internal constant SALT = bytes32(uint256(0x5A17));

    function setUp() public {
        address[] memory owners = new address[](3);
        owners[0] = address(0x1);
        owners[1] = address(0x2);
        owners[2] = address(0x3);
        safe = new MockSafe(MIN_THRESHOLD, owners);
        diamond = _deployGovernedSafeDiamondCut(admin, address(safe), MIN_THRESHOLD, MIN_DELAY);
        dummy = new DummyFacet();
        vm.warp(1_000_000); // sane baseline timestamp
    }

    function _addPingCut() internal view returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DummyFacet.ping.selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Add, functionSelectors: sels});
    }

    function _opId(FacetCut[] memory cuts, address init, bytes memory cd, bytes32 salt)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(cuts, init, cd, salt));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       SELECTOR / SLOT / ERC-165 INVARIANTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The module deliberately does NOT serve the canonical cut selector — every cut is delayed.
    function test_DoesNotServeCanonicalCutSelector() public view {
        assertEq(loupe.facetAddress(bytes4(0x1f931c1c)), address(0), "must not bind synchronous diamondCut");
    }

    function _erc7201Slot(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff));
    }

    function test_StorageSlotDerivation() public pure {
        assertEq(
            GOVERNED_SAFE_DIAMOND_CUT_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.GovernedSafeDiamondCut"),
            "GovernedSafeDiamondCut storage slot mismatch"
        );
    }

    /// @notice The scheduling ABI is a genuinely new interface with its own ERC-165 id (0xacb1aeb6),
    ///         registered at init.
    function test_InterfaceIdRegistered() public view {
        bytes4 id = type(IGovernedSafeDiamondCut).interfaceId;
        assertEq(id, bytes4(0xacb1aeb6), "IGovernedSafeDiamondCut interfaceId comment is stale");
        assertTrue(erc165.supportsInterface(id), "interface must be advertised via ERC-165");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitPinsSafeAndDelay() public view {
        assertEq(cut.safe(), address(safe), "safe must be pinned");
        assertEq(cut.minDelay(), MIN_DELAY, "minDelay must be pinned");
    }

    function test_InitRejectsZeroSafe() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            deployer.buildCuts(admin, address(0), MIN_THRESHOLD, MIN_DELAY);
        Diamond d = new Diamond();
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutZeroSafe.selector));
        d.initialize(cuts, init, cd);
    }

    function test_InitRejectsThresholdTooLow() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = deployer.buildCuts(admin, address(safe), 3, MIN_DELAY);
        Diamond d = new Diamond();
        vm.expectRevert(
            abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutThresholdTooLow.selector, uint256(2), uint256(3))
        );
        d.initialize(cuts, init, cd);
    }

    /// @notice minDelay may be 0 (documented risk): init succeeds.
    function test_InitAllowsZeroDelay() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            deployer.buildCuts(admin, address(safe), MIN_THRESHOLD, 0);
        Diamond d = new Diamond();
        d.initialize(cuts, init, cd);
        assertEq(GovernedSafeDiamondCut(address(d)).minDelay(), 0, "zero delay must be permitted");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       SCHEDULE -> DELAY -> EXECUTE
    //////////////////////////////////////////////////////////////////////////*//

    function test_ScheduleSetsEtaAndEmits() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        uint256 expectedEta = block.timestamp + MIN_DELAY;

        vm.expectEmit(true, true, false, true, address(diamond));
        emit IGovernedSafeDiamondCut.CutScheduled(id, 1, address(0), SALT, expectedEta);
        vm.prank(address(safe));
        bytes32 returnedId = cut.scheduleCut(cuts, address(0), "", SALT);

        assertEq(returnedId, id, "returned id mismatch");
        assertEq(cut.getTimestamp(id), expectedEta, "eta must be stored");
        assertTrue(cut.isOperationPending(id), "operation must be pending before eta");
        assertFalse(cut.isOperationReady(id), "operation must not be ready before eta");
    }

    function test_ScheduleUnauthorizedReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        cut.scheduleCut(cuts, address(0), "", SALT);
    }

    function test_ScheduleBlockedWhileStopped() public {
        vm.prank(admin);
        es.addGuardian(admin);
        vm.prank(admin);
        es.emergencyStop("freeze");

        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        cut.scheduleCut(cuts, address(0), "", SALT);
    }

    function test_ScheduleDuplicateReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        cut.scheduleCut(cuts, address(0), "", SALT);

        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IGovernedSafeDiamondCut.CutAlreadyScheduled.selector, id));
        cut.scheduleCut(cuts, address(0), "", SALT);
    }

    /// @notice Executing before eta reverts CutNotReady(id, eta).
    function test_ExecuteTooEarlyReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        cut.scheduleCut(cuts, address(0), "", SALT);
        uint256 eta = cut.getTimestamp(id);

        // Warp to one second before eta.
        vm.warp(eta - 1);
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IGovernedSafeDiamondCut.CutNotReady.selector, id, eta));
        cut.executeCut(cuts, address(0), "", SALT);
    }

    /// @notice Executing an unscheduled id reverts CutNotScheduled(id).
    function test_ExecuteUnscheduledReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IGovernedSafeDiamondCut.CutNotScheduled.selector, id));
        cut.executeCut(cuts, address(0), "", SALT);
    }

    /// @notice Full happy path: schedule, wait out the delay, execute — selector is bound and the
    ///         operation is cleared (done) and recorded in the registry.
    function test_ScheduleDelayExecute() public {
        vm.warp(2_000_000);
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);

        vm.prank(address(safe));
        cut.scheduleCut(cuts, address(0), "", SALT);
        uint256 eta = cut.getTimestamp(id);

        vm.warp(eta); // exactly ready
        assertTrue(cut.isOperationReady(id), "operation must be ready at eta");

        vm.expectEmit(true, false, false, false, address(diamond));
        emit IGovernedSafeDiamondCut.CutExecuted(id);
        vm.prank(address(safe));
        cut.executeCut(cuts, address(0), "", SALT);

        assertEq(loupe.facetAddress(DummyFacet.ping.selector), address(dummy), "ping selector must be bound");
        // Operation cleared: not pending, not ready, done.
        assertEq(cut.getTimestamp(id), 0, "eta must be cleared after execute");
        assertFalse(cut.isOperationPending(id));
        assertFalse(cut.isOperationReady(id));
        assertTrue(cut.isOperationDone(id), "operation must report done after execute");

        // Registry recorded.
        assertEq(cut.cutCount(), 1, "cut must be recorded");
        IUpgradeRegistry.CutRecord memory rec = cut.getCutRecord(1);
        assertEq(rec.executor, address(safe), "executor must be the Safe");
        assertEq(rec.cutHash, keccak256(abi.encode(cuts, address(0), bytes(""))), "cutHash must bind payload");
    }

    /// @notice Execute is Safe-gated even after maturity: a stranger reverts.
    function test_ExecuteUnauthorizedReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        cut.scheduleCut(cuts, address(0), "", SALT);
        vm.warp(cut.getTimestamp(id));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        cut.executeCut(cuts, address(0), "", SALT);
    }

    /// @notice Execute is blocked while emergency-stopped (even after maturity).
    function test_ExecuteBlockedWhileStopped() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        cut.scheduleCut(cuts, address(0), "", SALT);
        vm.warp(cut.getTimestamp(id));

        vm.prank(admin);
        es.addGuardian(admin);
        vm.prank(admin);
        es.emergencyStop("freeze");

        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        cut.executeCut(cuts, address(0), "", SALT);
    }

    /// @notice An execute that touches a frozen selector reverts FrozenSelectorProtected.
    function test_ExecuteFrozenSelectorReverts() public {
        bytes4 sel = DummyFacet.ping.selector;
        // Freeze the selector first.
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = sel;
        vm.prank(address(safe));
        cut.freezeSelectors(sels);

        // Schedule a REMOVE of the frozen selector, mature it, then execute -> revert.
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(0), action: FacetCutAction.Remove, functionSelectors: sels});
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        cut.scheduleCut(cuts, address(0), "", SALT);
        vm.warp(cut.getTimestamp(id));

        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, sel));
        cut.executeCut(cuts, address(0), "", SALT);
    }

    /// @notice The same payload can be re-scheduled under a different salt (distinct operation ids).
    function test_SaltDisambiguatesPayloads() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 salt2 = bytes32(uint256(0xBEEF));
        vm.prank(address(safe));
        bytes32 id1 = cut.scheduleCut(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        bytes32 id2 = cut.scheduleCut(cuts, address(0), "", salt2);
        assertTrue(id1 != id2, "distinct salts must yield distinct ids");
        assertTrue(cut.isOperationPending(id1) && cut.isOperationPending(id2), "both scheduled");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CANCEL
    //////////////////////////////////////////////////////////////////////////*//

    function test_CancelClearsPendingOperation() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        cut.scheduleCut(cuts, address(0), "", SALT);
        assertTrue(cut.isOperationPending(id), "scheduled");

        vm.expectEmit(true, false, false, false, address(diamond));
        emit IGovernedSafeDiamondCut.CutCancelled(id);
        vm.prank(address(safe));
        cut.cancelCut(id);

        assertEq(cut.getTimestamp(id), 0, "eta must be cleared after cancel");
        assertFalse(cut.isOperationPending(id), "must not be pending after cancel");

        // A cancelled operation cannot be executed even after the original eta passes.
        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IGovernedSafeDiamondCut.CutNotScheduled.selector, id));
        cut.executeCut(cuts, address(0), "", SALT);
    }

    function test_CancelUnauthorizedReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        cut.scheduleCut(cuts, address(0), "", SALT);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        cut.cancelCut(id);
    }

    function test_CancelUnscheduledReverts() public {
        bytes32 id = bytes32(uint256(0xDEAD));
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IGovernedSafeDiamondCut.CutNotScheduled.selector, id));
        cut.cancelCut(id);
    }

    /// @notice After cancel, the same payload+salt can be re-scheduled and executed cleanly.
    function test_CanRescheduleAfterCancel() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        cut.scheduleCut(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        cut.cancelCut(id);

        vm.prank(address(safe));
        cut.scheduleCut(cuts, address(0), "", SALT);
        vm.warp(cut.getTimestamp(id));
        vm.prank(address(safe));
        cut.executeCut(cuts, address(0), "", SALT);
        assertEq(loupe.facetAddress(DummyFacet.ping.selector), address(dummy), "re-scheduled cut must apply");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       SET MIN DELAY / SAFE ROTATION
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetMinDelay() public {
        vm.expectEmit(false, false, false, true, address(diamond));
        emit IGovernedSafeDiamondCut.MinDelayChanged(MIN_DELAY, 5 days);
        vm.prank(address(safe));
        cut.setMinDelay(5 days);
        assertEq(cut.minDelay(), 5 days, "minDelay must update");

        // New schedule uses the new delay.
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        cut.scheduleCut(cuts, address(0), "", SALT);
        assertEq(cut.getTimestamp(id), block.timestamp + 5 days, "new schedule must use new delay");
    }

    function test_SetMinDelayUnauthorizedReverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        cut.setMinDelay(1 days);
    }

    function test_SetSafeRotatesAuthority() public {
        address[] memory owners = new address[](2);
        owners[0] = address(0x4);
        owners[1] = address(0x5);
        MockSafe newSafe = new MockSafe(2, owners);

        vm.expectEmit(true, true, false, false, address(diamond));
        emit ISafeAuthority.SafeRotated(address(safe), address(newSafe));
        vm.prank(address(safe));
        cut.setSafe(address(newSafe));
        assertEq(cut.safe(), address(newSafe), "safe must rotate");

        // New Safe can schedule; old Safe cannot.
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, address(safe)));
        cut.scheduleCut(cuts, address(0), "", SALT);

        vm.prank(address(newSafe));
        cut.scheduleCut(cuts, address(0), "", SALT);
    }

    function test_SetSafeUnauthorizedReverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        cut.setSafe(address(0xCAFE));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       EMERGENCY REMOVAL-ONLY CUT
    //////////////////////////////////////////////////////////////////////////*//

    address internal guardian = address(0x6044D1A11);

    function _bindPingViaTimelock() internal {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        cut.scheduleCut(cuts, address(0), "", SALT);
        vm.warp(cut.getTimestamp(id));
        vm.prank(address(safe));
        cut.executeCut(cuts, address(0), "", SALT);
    }

    function _removeCut(bytes4 _sel) internal pure returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = _sel;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(0), action: FacetCutAction.Remove, functionSelectors: sels});
    }

    /// @notice Guardian emergency removal bypasses the timelock entirely (zero-delay), even mid-stop.
    function test_EmergencyRemove_ZeroDelayBypassesTimelock() public {
        _bindPingViaTimelock();
        assertEq(loupe.facetAddress(DummyFacet.ping.selector), address(dummy), "ping must be live");

        vm.prank(admin);
        es.addGuardian(guardian);
        FacetCut[] memory cuts = _removeCut(DummyFacet.ping.selector);
        vm.prank(guardian);
        cut.emergencyRemoveCut(cuts);
        assertEq(loupe.facetAddress(DummyFacet.ping.selector), address(0), "emergency removal must unbind instantly");
    }

    function test_EmergencyRemove_StrangerReverts() public {
        _bindPingViaTimelock();
        FacetCut[] memory cuts = _removeCut(DummyFacet.ping.selector);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, EMERGENCY_GUARDIAN_ROLE
            )
        );
        cut.emergencyRemoveCut(cuts);
    }

    function test_EmergencyRemove_RejectsAdd() public {
        vm.prank(admin);
        es.addGuardian(guardian);
        FacetCut[] memory cuts = _addPingCut(); // Add
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(IEmergencyCut.EmergencyCutMustBeRemoveOnly.selector, uint8(FacetCutAction.Add))
        );
        cut.emergencyRemoveCut(cuts);
    }

    function test_EmergencyRemove_WorksWhileStopped() public {
        _bindPingViaTimelock();
        vm.prank(admin);
        es.addGuardian(admin);
        vm.prank(admin);
        es.emergencyStop("incident");

        FacetCut[] memory cuts = _removeCut(DummyFacet.ping.selector);
        vm.prank(admin);
        cut.emergencyRemoveCut(cuts);
        assertEq(loupe.facetAddress(DummyFacet.ping.selector), address(0), "emergency removal must work during a stop");
    }
}
